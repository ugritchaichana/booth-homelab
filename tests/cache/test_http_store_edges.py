import hashlib
import os
import socket
import threading
import unittest
from unittest import mock

from support import key_for
from build_cache.adapters.http_store import HttpStore
from build_cache.domain.models import Manifest, StoreUnavailable, WriteFailed, WriteRefused

DIGEST = hashlib.sha256(b"payload").hexdigest()
KEY = key_for("nuget", "edges")
PASSWORD = "edge-case-password"


class ScriptedServer:
    """Answers each connection from a script: an int is the HTTP status to send, "drop" closes the socket."""

    def __init__(self, *script):
        self.script, self.requests = list(script), []
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen()
        self.listener.settimeout(0.05)
        self.stopped = False
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    @property
    def url(self):
        return "http://127.0.0.1:%d" % self.listener.getsockname()[1]

    def close(self):
        self.stopped = True
        self.thread.join(5)
        self.listener.close()

    def serve(self):
        while not self.stopped:
            try:
                connection, _ = self.listener.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(5)
                action = self.script.pop(0) if self.script else "drop"
                if action != "drop":
                    self.requests.append(self.read_request(connection))
                    connection.sendall(b"HTTP/1.1 %d Scripted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" % action)

    @staticmethod
    def read_request(connection):
        data = b""
        while b"\r\n\r\n" not in data:
            data += connection.recv(4096)
        head, _, body = data.partition(b"\r\n\r\n")
        length = int(next((l.split(b":")[1] for l in head.split(b"\r\n") if l.lower().startswith(b"content-length")), b"0"))
        while len(body) < length:
            body += connection.recv(4096)
        return head.split(b"\r\n")[0].decode()


class HttpStoreEdgeTests(unittest.TestCase):
    def serve(self, *script):
        server = ScriptedServer(*script)
        self.addCleanup(server.close)
        return server

    def writer(self, server):
        return HttpStore(server.url, PASSWORD, connect_timeout=2.0, read_timeout=5.0)

    def test_a_url_that_is_not_http_with_a_host_is_refused(self):
        for url in ("https://cache.example", "http:///no-host", "ftp://cache.example", ""):
            with self.assertRaisesRegex(ValueError, "http URL with a host", msg=url):
                HttpStore(url)

    def test_a_url_without_a_port_means_port_80(self):
        self.assertEqual(HttpStore("http://cache.example")._port, 80)
        self.assertEqual(HttpStore("http://cache.example:8080")._port, 8080)

    def test_a_malformed_key_or_digest_is_refused_before_any_request(self):
        server = self.serve()
        store = self.writer(server)
        manifest = Manifest(key=KEY, kind="nuget", sha256=DIGEST, size=1, compression="gzip")
        for call in (
            lambda: store.get_pointer("nuget-latest"),
            lambda: store.put_pointer("nuget-latest", manifest),
            lambda: store.get_blob("zz"),
            lambda: store.put_blob("zz", b"x"),
        ):
            with self.assertRaises(ValueError):
                call()
        self.assertEqual(server.requests, [])

    def test_from_env_reads_the_url_the_password_and_the_timeouts(self):
        server = self.serve(200, 200)
        env = {"CACHE_URL": server.url, "CACHE_WRITER_PASSWORD": PASSWORD, "CACHE_CONNECT_TIMEOUT": "0.5", "CACHE_READ_TIMEOUT": "7"}
        with mock.patch.dict(os.environ, env, clear=True):
            store = HttpStore.from_env()
        store.put_blob(DIGEST, b"payload")
        self.assertEqual((store._connect_timeout, store._read_timeout), (0.5, 7.0))
        self.assertEqual(len(server.requests), 2)

    def test_from_env_without_a_password_or_with_an_empty_one_cannot_write(self):
        server = self.serve()
        for env in ({"CACHE_URL": server.url}, {"CACHE_URL": server.url, "CACHE_WRITER_PASSWORD": ""}):
            with mock.patch.dict(os.environ, env, clear=True):
                store = HttpStore.from_env()
            with self.assertRaises(WriteRefused):
                store.put_blob(DIGEST, b"payload")
        self.assertEqual(server.requests, [])

    def test_a_connection_dropped_on_a_read_is_the_store_being_unavailable(self):
        store = self.writer(self.serve("drop"))
        with self.assertRaisesRegex(StoreUnavailable, "GET failed"):
            store.get_blob(DIGEST)

    def test_a_dropped_upload_is_a_failed_write_even_when_the_follow_up_probe_is_dropped_too(self):
        store = self.writer(self.serve(200, "drop", "drop"))
        with self.assertRaisesRegex(WriteFailed, "connection dropped"):
            store.put_blob(DIGEST, b"payload")

    def test_an_unexpected_status_on_a_write_is_the_store_being_unavailable(self):
        store = self.writer(self.serve(404))
        with self.assertRaisesRegex(StoreUnavailable, "write answered HTTP 404"):
            store.put_blob(DIGEST, b"payload")

    def test_a_403_on_a_write_is_a_refusal(self):
        store = self.writer(self.serve(403))
        with self.assertRaisesRegex(WriteRefused, "HTTP 403"):
            store.put_blob(DIGEST, b"payload")


if __name__ == "__main__":
    unittest.main()
