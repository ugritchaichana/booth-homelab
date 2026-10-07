import argparse
import contextlib
import hashlib
import io
import json
import os
import shutil
import socket
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest import mock

from support import key_for
from build_cache import cli
from build_cache.adapters.http_store import HttpStore
from build_cache.adapters.tar_archiver import TarArchiver
from build_cache.application.restore import restore
from build_cache.application.save import save
from build_cache.domain.models import Manifest, StoreUnavailable, WriteRefused
from build_cache.domain.policy import WriteDecision

PASSWORD = "s3cret-Pa55-do-not-leak"
ALLOW = WriteDecision(True, "test")


class FakeCacheServer:
    def __init__(self, delay: float = 0.0):
        self.ac, self.cas, self.requests, self.delay = {}, {}, [], delay
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _reply(self, status, body=b""):
                self.send_response(status)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                if self.command != "HEAD":
                    self.wfile.write(body)

            def _store(self):
                kind, _, name = self.path.strip("/").partition("/")
                return {"ac": outer.ac, "cas": outer.cas}.get(kind), kind, name

            def do_GET(self):
                outer.requests.append((self.command, self.path, self.headers.get("Authorization")))
                time.sleep(outer.delay)
                table, _, name = self._store()
                if table is None or name not in table:
                    return self._reply(404)
                self._reply(200, table[name])

            do_HEAD = do_GET

            def do_PUT(self):
                outer.requests.append((self.command, self.path, self.headers.get("Authorization")))
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                import base64

                expected = "Basic " + base64.b64encode(f"ci-writer:{PASSWORD}".encode()).decode()
                if self.headers.get("Authorization") != expected:
                    return self._reply(401)
                table, kind, name = self._store()
                if table is None:
                    return self._reply(404)
                if kind == "cas" and hashlib.sha256(body).hexdigest() != name:
                    return self._reply(400)
                table[name] = body
                self._reply(200)

        class QuietServer(ThreadingHTTPServer):
            def handle_error(self, request, client_address):
                pass

        self.server = QuietServer(("localhost", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def url(self):
        host, port = self.server.server_address[:2]
        return f"http://{host}:{port}"

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *exc):
        self.server.shutdown()
        self.server.server_close()


def closed_port_url():
    sock = socket.socket()
    sock.bind(("localhost", 0))
    host, port = sock.getsockname()[:2]
    sock.close()
    return f"http://{host}:{port}"


class HttpStoreTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.src, self.dest = self.tmp / "src", self.tmp / "dest"
        (self.src / "obj").mkdir(parents=True)
        (self.src / "obj" / "a.dll").write_bytes(b"binary-a")
        self.archiver = TarArchiver(prefer_zstd=False)
        self.key = key_for("dotnet-outputs", "http")
        self.server = FakeCacheServer()
        self.server.__enter__()
        self.addCleanup(self.server.__exit__)

    def writer(self, **kwargs):
        return HttpStore(self.server.url, PASSWORD, **kwargs)

    def reader(self, **kwargs):
        return HttpStore(self.server.url, None, **kwargs)

    def test_authorized_write_is_accepted_and_a_reader_gets_a_hit(self):
        saved = save("dotnet-outputs", self.key, self.src, ["obj"], self.writer(), self.archiver, ALLOW)
        self.assertEqual(saved.status, "saved")
        self.assertIn(self.key, self.server.ac)
        hit = restore("dotnet-outputs", self.key, self.dest, self.reader(), self.archiver)
        self.assertEqual(hit.status, "hit")
        self.assertEqual((self.dest / "obj" / "a.dll").read_bytes(), b"binary-a")

    def test_unknown_key_is_a_miss(self):
        self.assertEqual(restore("dotnet-outputs", self.key, self.dest, self.reader(), self.archiver).status, "miss")
        self.assertIsNone(self.reader().get_blob("0" * 64))

    def test_reads_are_anonymous(self):
        save("dotnet-outputs", self.key, self.src, ["obj"], self.writer(), self.archiver, ALLOW)
        self.server.requests.clear()
        restore("dotnet-outputs", self.key, self.dest, self.writer(), self.archiver)
        reads = [r for r in self.server.requests if r[0] == "GET"]
        self.assertEqual(len(reads), 2)
        self.assertEqual([r[2] for r in reads], [None, None])

    def test_write_with_a_wrong_password_is_refused_and_counted_not_raised(self):
        wrong = HttpStore(self.server.url, "not-the-password")
        result = save("dotnet-outputs", self.key, self.src, ["obj"], wrong, self.archiver, ALLOW)
        self.assertEqual(result.status, "refused")
        self.assertEqual(self.server.ac, {})

    def test_write_without_a_password_is_refused_before_any_request(self):
        result = save("dotnet-outputs", self.key, self.src, ["obj"], self.reader(), self.archiver, ALLOW)
        self.assertEqual(result.status, "refused")
        self.assertEqual(self.server.requests, [])

    def test_cas_put_with_a_body_that_does_not_match_its_digest_is_rejected(self):
        with self.assertRaises(WriteRefused):
            self.writer().put_blob(hashlib.sha256(b"one").hexdigest(), b"another")
        self.assertEqual(self.server.cas, {})

    def test_tampered_blob_on_the_server_is_a_rejected_restore(self):
        save("dotnet-outputs", self.key, self.src, ["obj"], self.writer(), self.archiver, ALLOW)
        sha = self.server.ac and Manifest.from_json(self.server.ac[self.key].decode()).sha256
        self.server.cas[sha] = b"tampered"
        result = restore("dotnet-outputs", self.key, self.dest, self.reader(), self.archiver)
        self.assertEqual(result.status, "rejected")

    def test_server_down_is_a_miss_and_a_save_is_unreachable(self):
        dead = HttpStore(closed_port_url(), PASSWORD, connect_timeout=0.3)
        self.assertEqual(restore("dotnet-outputs", self.key, self.dest, dead, self.archiver).status, "miss")
        self.assertEqual(save("dotnet-outputs", self.key, self.src, ["obj"], dead, self.archiver, ALLOW).status, "unreachable")

    def test_slow_server_times_out_as_a_miss(self):
        self.server.delay = 1.5
        slow = self.reader(read_timeout=0.3)
        started = time.monotonic()
        result = restore("dotnet-outputs", self.key, self.dest, slow, self.archiver)
        self.assertEqual(result.status, "miss")
        self.assertLess(time.monotonic() - started, 1.4)

    def test_server_error_is_unreachable_not_a_hit(self):
        with mock.patch.object(HttpStore, "_request", return_value=(503, b"")):
            with self.assertRaises(StoreUnavailable):
                self.reader().get_pointer(self.key)

    def test_password_never_appears_in_outputs_logs_or_exception_text(self):
        seen = []
        wrong_server_down = HttpStore(closed_port_url(), PASSWORD, connect_timeout=0.3)
        for store in (self.writer(), HttpStore(self.server.url, PASSWORD + "x"), wrong_server_down):
            with self.assertLogs("build_cache", level="INFO") as logs:
                outcomes = [
                    save("dotnet-outputs", self.key, self.src, ["obj"], store, self.archiver, ALLOW),
                    restore("dotnet-outputs", self.key, self.dest, store, self.archiver),
                ]
            seen += logs.output + [json.dumps(o.as_record()) for o in outcomes]
        try:
            wrong_server_down.get_blob("0" * 64)
        except StoreUnavailable as exc:
            seen.append(f"{exc!r} {exc}")
        stats, summary = self.tmp / "stats.jsonl", self.tmp / "summary.md"
        with mock.patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(summary)}), contextlib.redirect_stdout(io.StringIO()):
            cli.emit(outcomes[0], argparse.Namespace(stats_file=str(stats)))
        seen += [stats.read_text(), summary.read_text()]
        for text in seen:
            self.assertNotIn(PASSWORD, text)
        self.assertNotIn("Basic", " ".join(seen))

    def test_cli_picks_the_http_store_from_the_environment(self):
        env = {"CACHE_URL": self.server.url, "CACHE_WRITER_PASSWORD": PASSWORD}
        with mock.patch.dict(os.environ, env):
            self.assertIsInstance(cli.make_store(None), HttpStore)
            self.assertNotIsInstance(cli.make_store(f"fs:{self.tmp}"), HttpStore)
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(cli.make_store(None))


if __name__ == "__main__":
    unittest.main()
