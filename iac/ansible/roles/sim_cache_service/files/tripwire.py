#!/usr/bin/env python3
import argparse
import http.client
import json
import os
import re
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade", "expect"}
CREDENTIAL = re.compile(r"^AWS4-HMAC-SHA256\s+Credential=([^/,\s]+)/")
QUERY_AUTH = {"x-amz-credential", "x-amz-signature", "awsaccesskeyid", "signature"}
REJECT_CODES = (b"<Code>InvalidAccessKeyId</Code>", b"<Code>SignatureDoesNotMatch</Code>")
DENIED = b'<?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code><Message>Access Denied.</Message></Error>'


def authorizations(headers):
    if hasattr(headers, "get_all"):
        return headers.get_all("Authorization") or []
    return [headers["Authorization"]] if "Authorization" in headers else []


def claimed_key(headers):
    values = authorizations(headers)
    match = CREDENTIAL.match(values[0]) if len(values) == 1 else None
    return match.group(1) if match else None


def violation(headers, query, allowed):
    if any(name.lower() in QUERY_AUTH for name in query):
        return "credential in the query string"
    values = authorizations(headers)
    if len(values) > 1:
        return "multiple authorization headers"
    if not values or not values[0]:
        return "anonymous request"
    key = claimed_key(headers)
    if key is None:
        return "unsupported authorization"
    if key not in allowed:
        return "unknown access key"
    return None


class Proxy(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 120

    def log_message(self, *_):
        pass

    def deny(self, status=403, body=DENIED):
        self.entry["status"] = status
        self.close_connection = True
        self.send_response(status)
        self.send_header("Content-Type", "application/xml")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self):
        self.entry = {"time": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "remote": self.client_address[0], "method": self.command, "path": urlsplit(self.path).path, "identity": self.server.allowed.get(claimed_key(self.headers))}
        try:
            self.proxy()
        except OSError:
            self.close_connection = True
        finally:
            self.server.audit(self.entry)

    def proxy(self):
        reason = violation(self.headers, parse_qs(urlsplit(self.path).query, keep_blank_values=True), self.server.allowed)
        if reason:
            self.server.trip(reason)
            self.entry["tripped"] = reason
            return self.deny()
        if self.headers.get("Transfer-Encoding"):
            return self.deny(411, b"")
        try:
            remaining = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self.deny(400, b"")
        upstream = http.client.HTTPConnection(*self.server.upstream, timeout=600)
        try:
            upstream.putrequest(self.command, self.path, skip_host=True, skip_accept_encoding=True)
            for name, value in self.headers.items():
                if name.lower() not in HOP:
                    upstream.putheader(name, value)
            upstream.endheaders()
            while remaining > 0:
                chunk = self.rfile.read(min(65536, remaining))
                if not chunk:
                    raise ConnectionError("client closed during upload")
                upstream.send(chunk)
                remaining -= len(chunk)
            self.relay(upstream.getresponse())
        except (http.client.HTTPException, ConnectionError, TimeoutError):
            if "status" not in self.entry:
                self.deny(502, b"")
        finally:
            upstream.close()

    def relay(self, response):
        self.entry["status"] = response.status
        head = self.command == "HEAD"
        buffered = None
        reject = False
        if response.status == 403:
            if head:
                reject = True
            else:
                buffered = response.read(65536)
                reject = any(code in buffered for code in REJECT_CODES)
        if reject:
            self.server.trip("credentials rejected by the store")
            self.entry["tripped"] = "credentials rejected by the store"
        self.send_response_only(response.status, response.reason)
        sized = False
        for name, value in response.getheaders():
            if name.lower() in HOP:
                continue
            if name.lower() == "content-length":
                sized = True
                value = str(len(buffered)) if buffered is not None else value
            self.send_header(name, value)
        if not sized and not head and response.status not in (204, 304):
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        if head:
            return
        if buffered is not None:
            self.wfile.write(buffered)
            return
        while True:
            chunk = response.read(65536)
            if not chunk:
                return
            self.wfile.write(chunk)

    do_GET = do_PUT = do_HEAD = do_POST = do_DELETE = do_OPTIONS = do_PATCH = handle_any


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 128

    def __init__(self, args):
        host, _, port = args.listen.rpartition(":")
        super().__init__((host, int(port)), Proxy)
        self.upstream = (args.upstream.rpartition(":")[0], int(args.upstream.rpartition(":")[2]))
        self.allowed = dict(line.strip().split(":", 1)[::-1] for line in open(args.allowed_file, encoding="utf-8") if ":" in line)
        self.marker = os.path.join(args.state_dir, "tripwire", "tripped")
        self.log_file, self.log_max = args.log_file, args.log_max_bytes
        self.lock = threading.Lock()

    def trip(self, reason):
        if os.path.exists(self.marker):
            return
        temp = self.marker + ".tmp"
        with open(temp, "w", encoding="utf-8") as handle:
            handle.write("%s %s\n" % (time.strftime("%Y-%m-%dT%H:%M:%S%z"), reason))
        os.replace(temp, self.marker)

    def audit(self, entry):
        with self.lock:
            os.makedirs(os.path.dirname(self.log_file), exist_ok=True)
            if os.path.exists(self.log_file) and os.path.getsize(self.log_file) > self.log_max:
                os.replace(self.log_file, self.log_file + ".1")
            with open(self.log_file, "a", encoding="utf-8") as handle:
                handle.write(json.dumps(entry, separators=(",", ":")) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", required=True)
    parser.add_argument("--upstream", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--log-file", required=True)
    parser.add_argument("--log-max-bytes", type=int, default=64 << 20)
    parser.add_argument("--allowed-file", required=True)
    Server(parser.parse_args()).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
