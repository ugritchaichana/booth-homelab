from __future__ import annotations

import os
import tempfile
from pathlib import Path

from ..domain.models import KEY_RE, SHA256_RE, Manifest, StoreUnavailable


class FilesystemStore:
    def __init__(self, root: Path) -> None:
        self._pointers = Path(root) / "pointers"
        self._blobs = Path(root) / "blobs"

    def get_pointer(self, key: str) -> Manifest | None:
        text = self._read(self._pointer_path(key))
        return None if text is None else Manifest.from_json(text.decode("utf-8", "replace"))

    def put_pointer(self, key: str, manifest: Manifest) -> None:
        self._write_atomic(self._pointer_path(key), manifest.to_json().encode("utf-8"))

    def get_blob(self, sha256: str) -> bytes | None:
        return self._read(self._blob_path(sha256))

    def put_blob(self, sha256: str, data: bytes) -> None:
        path = self._blob_path(sha256)
        if path.is_file():
            return
        self._write_atomic(path, data)

    def _pointer_path(self, key: str) -> Path:
        if not KEY_RE.match(key):
            raise ValueError(f"malformed key: {key!r}")
        return self._pointers / f"{key}.json"

    def _blob_path(self, sha256: str) -> Path:
        if not SHA256_RE.match(sha256):
            raise ValueError(f"malformed blob digest: {sha256!r}")
        return self._blobs / sha256[:2] / sha256

    @staticmethod
    def _read(path: Path) -> bytes | None:
        try:
            return path.read_bytes()
        except FileNotFoundError:
            return None
        except OSError as exc:
            raise StoreUnavailable(str(exc)) from exc

    @staticmethod
    def _write_atomic(path: Path, data: bytes) -> None:
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-")
            try:
                with os.fdopen(fd, "wb") as handle:
                    handle.write(data)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(tmp, path)
            except BaseException:
                Path(tmp).unlink(missing_ok=True)
                raise
        except OSError as exc:
            raise StoreUnavailable(str(exc)) from exc
