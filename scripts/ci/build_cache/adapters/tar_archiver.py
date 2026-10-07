from __future__ import annotations

import gzip
import io
import os
import shutil
import subprocess
import tarfile
from pathlib import Path, PurePosixPath
from typing import Sequence

from ..application.ports import Packed
from ..domain.models import ArchiveRejected

FIXED_MTIME = 315532800


def _normalize(info: tarfile.TarInfo) -> tarfile.TarInfo:
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    info.mtime = FIXED_MTIME
    return info


def _walk(root: Path, relative: PurePosixPath):
    full = root / relative
    if not os.path.lexists(full):
        return
    yield relative
    if full.is_dir() and not full.is_symlink():
        for entry in sorted(os.scandir(full), key=lambda e: e.name):
            yield from _walk(root, relative / entry.name)


class TarArchiver:
    def __init__(self, prefer_zstd: bool = True) -> None:
        self._zstd = shutil.which("zstd") if prefer_zstd else None

    def pack(self, root: Path, paths: Sequence[str]) -> Packed | None:
        buffer = io.BytesIO()
        count = 0
        seen: set[PurePosixPath] = set()
        with tarfile.open(fileobj=buffer, mode="w", format=tarfile.PAX_FORMAT) as tar:
            for path in sorted(paths):
                relative = PurePosixPath(path)
                if relative.is_absolute() or ".." in relative.parts:
                    raise ValueError(f"archive path must stay under the root: {path!r}")
                for member in _walk(root, relative):
                    if member in seen or str(member) == ".":
                        continue
                    seen.add(member)
                    info = _normalize(tar.gettarinfo(str(root / member), arcname=member.as_posix()))
                    if info.isreg():
                        with open(root / member, "rb") as handle:
                            tar.addfile(info, handle)
                    else:
                        tar.addfile(info)
                    count += 1
        if count == 0:
            return None
        return self._compress(buffer.getvalue())

    def unpack(self, data: bytes, compression: str, root: Path) -> list[str]:
        raw = self._decompress(data, compression)
        root = Path(root)
        root.mkdir(parents=True, exist_ok=True)
        try:
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r") as tar:
                members = tar.getmembers()
                for member in members:
                    if member.name.startswith(("/", "\\")):
                        raise ArchiveRejected(f"absolute member path: {member.name!r}")
                    tarfile.data_filter(member, str(root))
                tar.extractall(path=root, members=members, filter="data")
        except (tarfile.FilterError, tarfile.TarError) as exc:
            raise ArchiveRejected(f"{type(exc).__name__}: {exc}") from exc
        return [m.name for m in members]

    def _compress(self, raw: bytes) -> Packed:
        if self._zstd:
            done = subprocess.run([self._zstd, "-q", "-T0", "-3", "-c"], input=raw, capture_output=True)
            if done.returncode == 0:
                return Packed(done.stdout, "zstd")
        return Packed(gzip.compress(raw, compresslevel=6, mtime=0), "gzip")

    def _decompress(self, data: bytes, compression: str) -> bytes:
        if compression == "gzip":
            try:
                return gzip.decompress(data)
            except (OSError, EOFError) as exc:
                raise ArchiveRejected(f"gzip stream unreadable: {exc}") from exc
        if compression == "zstd":
            if not self._zstd:
                raise ArchiveRejected("manifest says zstd but no zstd binary is available")
            done = subprocess.run([self._zstd, "-q", "-d", "-c"], input=data, capture_output=True)
            if done.returncode != 0:
                raise ArchiveRejected("zstd stream unreadable")
            return done.stdout
        raise ArchiveRejected(f"unknown compression {compression!r}")
