import sys
from pathlib import Path

PATCHED = (3, 13, 5)
REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "ci"))

import hashlib
import io
import subprocess
import tarfile

from build_cache.domain.models import Manifest, StoreUnavailable


class MemoryStore:
    def __init__(self):
        self.pointers, self.blobs, self.calls = {}, {}, []

    def get_pointer(self, key):
        self.calls.append(("get_pointer", key))
        return self.pointers.get(key)

    def put_pointer(self, key, manifest):
        self.calls.append(("put_pointer", key))
        self.pointers[key] = manifest

    def get_blob(self, sha256):
        self.calls.append(("get_blob", sha256))
        return self.blobs.get(sha256)

    def put_blob(self, sha256, data):
        self.calls.append(("put_blob", sha256))
        self.blobs[sha256] = data


class DownStore:
    def __init__(self, error):
        self.error = error

    def _fail(self, *_):
        raise self.error

    get_pointer = put_pointer = get_blob = put_blob = _fail


def key_for(kind, seed):
    return f"{kind}-{hashlib.sha256(seed.encode()).hexdigest()}"


def publish(store, key, kind, blob, compression="gzip", claimed_sha=None):
    sha = claimed_sha or hashlib.sha256(blob).hexdigest()
    store.blobs[sha] = blob
    store.pointers[key] = Manifest(key=key, kind=kind, sha256=sha, size=len(blob), compression=compression)


def tar_bytes(entries):
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as tar:
        for info, payload in entries:
            tar.addfile(info, io.BytesIO(payload) if payload is not None else None)
    return buffer.getvalue()


def file_info(name, size=0):
    info = tarfile.TarInfo(name)
    info.size = size
    return info


def link_info(name, target):
    info = tarfile.TarInfo(name)
    info.type = tarfile.SYMTYPE
    info.linkname = target
    return info


def device_info(name):
    info = tarfile.TarInfo(name)
    info.type = tarfile.CHRTYPE
    return info


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)
