from __future__ import annotations

import base64
import hashlib
import http.client
import os
from urllib.parse import urlsplit

from ..domain.models import KEY_RE, SHA256_RE, Manifest, BadRequest, StoreUnavailable, WriteFailed, WriteRefused

WRITER_USER = "ci-writer"
CONNECT_TIMEOUT = 2.0
READ_TIMEOUT = 60.0
EMPTY_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"


class _ConnectionDropped(StoreUnavailable):
    pass


class HttpStore:
    def __init__(
        self,
        base_url: str,
        writer_password: str | None = None,
        writer_user: str = WRITER_USER,
        connect_timeout: float = CONNECT_TIMEOUT,
        read_timeout: float = READ_TIMEOUT,
    ) -> None:
        parts = urlsplit(base_url)
        if parts.scheme != "http" or not parts.hostname:
            raise ValueError("CACHE_URL must be an http URL with a host")
        self._host, self._port = parts.hostname, parts.port or 80
        self._prefix = parts.path.rstrip("/")
        self._connect_timeout, self._read_timeout = connect_timeout, read_timeout
        token = base64.b64encode(f"{writer_user}:{writer_password}".encode()).decode() if writer_password else None
        self._write_headers = {"Authorization": f"Basic {token}"} if token else None
        self._authorized = False

    @classmethod
    def from_env(cls) -> "HttpStore":
        return cls(
            os.environ["CACHE_URL"],
            os.environ.get("CACHE_WRITER_PASSWORD") or None,
            connect_timeout=float(os.environ.get("CACHE_CONNECT_TIMEOUT", CONNECT_TIMEOUT)),
            read_timeout=float(os.environ.get("CACHE_READ_TIMEOUT", READ_TIMEOUT)),
        )

    def get_pointer(self, key: str) -> Manifest | None:
        body = self._get(f"/ac/{self._ac_name(key)}")
        return None if body is None else Manifest.from_json(body.decode("utf-8", "replace"))

    def put_pointer(self, key: str, manifest: Manifest) -> None:
        self._put(f"/ac/{self._ac_name(key)}", manifest.to_json().encode("utf-8"))

    def get_blob(self, sha256: str) -> bytes | None:
        return self._get(f"/cas/{self._checked_sha(sha256)}")

    def put_blob(self, sha256: str, data: bytes) -> None:
        self._put(f"/cas/{self._checked_sha(sha256)}", data)

    @staticmethod
    def _ac_name(key: str) -> str:
        if not KEY_RE.match(key):
            raise ValueError(f"malformed key: {key!r}")
        return hashlib.sha256(key.encode()).hexdigest()

    @staticmethod
    def _checked_sha(sha256: str) -> str:
        if not SHA256_RE.match(sha256):
            raise ValueError(f"malformed blob digest: {sha256!r}")
        return sha256

    def _get(self, path: str) -> bytes | None:
        status, body = self._request("GET", path, None, None)
        if status == 200:
            return body
        if status == 404:
            return None
        if status == 400:
            raise BadRequest("read answered HTTP 400")
        raise StoreUnavailable(f"read answered HTTP {status}")

    def _put(self, path: str, data: bytes) -> None:
        if self._write_headers is None:
            raise WriteRefused("no writer password configured")
        self._ensure_authorized()
        try:
            self._send_put(path, data)
        except _ConnectionDropped:
            try:
                self._probe()
            except StoreUnavailable:
                pass
            raise WriteFailed("connection dropped during the upload") from None

    def _ensure_authorized(self) -> None:
        if not self._authorized:
            self._probe()

    def _probe(self) -> None:
        self._send_put(f"/cas/{EMPTY_SHA256}", b"")
        self._authorized = True

    def _send_put(self, path: str, data: bytes) -> None:
        status, _ = self._request("PUT", path, data, self._write_headers)
        if status in (200, 201, 204):
            return
        if status == 400:
            raise BadRequest("write answered HTTP 400")
        if status in (401, 403):
            raise WriteRefused(f"server refused the write with HTTP {status}")
        if status >= 500:
            raise WriteFailed(f"server failed the write with HTTP {status}")
        raise StoreUnavailable(f"write answered HTTP {status}")

    def _request(self, method: str, path: str, body: bytes | None, headers: dict[str, str] | None) -> tuple[int, bytes]:
        connection = http.client.HTTPConnection(self._host, self._port, timeout=self._connect_timeout)
        try:
            connection.connect()
            connection.sock.settimeout(self._read_timeout)
            connection.request(method, self._prefix + path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.read()
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError) as exc:
            if method == "PUT":
                raise _ConnectionDropped(f"PUT failed: {type(exc).__name__}") from None
            raise StoreUnavailable(f"{method} failed: {type(exc).__name__}") from None
        except (OSError, http.client.HTTPException) as exc:
            raise StoreUnavailable(f"{method} failed: {type(exc).__name__}") from None
        finally:
            connection.close()
