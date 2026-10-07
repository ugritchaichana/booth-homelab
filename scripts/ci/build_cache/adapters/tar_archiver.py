from __future__ import annotations

import gzip
import io
import os
import shutil
import subprocess
import sys
import tarfile
import threading
import time
import zlib
from pathlib import Path, PurePosixPath
from typing import Sequence

from ..application.ports import Packed
from ..domain.models import ArchiveRejected, UnsafeRuntime
from ..domain.policy import ExtractionRules, member_allowed, supports_safe_extraction

FIXED_MTIME = 315532800
TAR_OVERHEAD_PER_MEMBER = 2048


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
    def __init__(self, prefer_zstd: bool = True, version_info: tuple[int, ...] | None = None) -> None:
        self._zstd = shutil.which("zstd") if prefer_zstd else None
        self._version = tuple(version_info) if version_info else tuple(sys.version_info[:3])

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

    def unpack(self, data: bytes, compression: str, root: Path, rules: ExtractionRules) -> list[str]:
        if not supports_safe_extraction(tuple(self._version)):
            raise UnsafeRuntime("python {} is below the patched tarfile releases".format(".".join(map(str, self._version[:3]))))
        limit = rules.max_bytes + rules.max_members * TAR_OVERHEAD_PER_MEMBER
        raw = self._decompress(data, compression, limit)
        root = Path(root)
        try:
            with tarfile.open(fileobj=io.BytesIO(raw), mode="r") as tar:
                members = tar.getmembers()
                self._check(members, root, rules)
                root.mkdir(parents=True, exist_ok=True)
                tar.extractall(path=root, members=members, filter="data")
        except (tarfile.FilterError, tarfile.TarError) as exc:
            raise ArchiveRejected(f"{type(exc).__name__}: {exc}") from exc
        return [m.name for m in members]

    @staticmethod
    def _check(members: list[tarfile.TarInfo], root: Path, rules: ExtractionRules) -> None:
        if len(members) > rules.max_members:
            raise ArchiveRejected(f"{len(members)} members exceed the limit of {rules.max_members}")
        if sum(m.size for m in members if m.isreg()) > rules.max_bytes:
            raise ArchiveRejected(f"content exceeds the limit of {rules.max_bytes} bytes")
        for member in members:
            if member.name.startswith(("/", "\\")):
                raise ArchiveRejected(f"absolute member path: {member.name!r}")
            if not member_allowed(member.name, rules):
                raise ArchiveRejected(f"member outside the allowed paths: {member.name!r}")
            tarfile.data_filter(member, str(root))

    def _compress(self, raw: bytes) -> Packed:
        if self._zstd:
            done = subprocess.run([self._zstd, "-q", "-T0", "-3", "-c"], input=raw, capture_output=True)
            if done.returncode == 0:
                return Packed(done.stdout, "zstd")
        return Packed(gzip.compress(raw, compresslevel=6, mtime=0), "gzip")

    def _decompress(self, data: bytes, compression: str, limit: int) -> bytes:
        if compression == "gzip":
            inflater = zlib.decompressobj(wbits=31)
            try:
                out = inflater.decompress(data, limit + 1)
            except zlib.error as exc:
                raise ArchiveRejected(f"gzip stream unreadable: {exc}") from exc
            if len(out) > limit or inflater.unconsumed_tail:
                raise ArchiveRejected("decompressed size exceeds the limit")
            if not inflater.eof:
                raise ArchiveRejected("gzip stream truncated")
            return out
        if compression == "zstd":
            if not self._zstd:
                raise ArchiveRejected("manifest says zstd but no zstd binary is available")
            return self._unzstd(data, limit)
        raise ArchiveRejected(f"unknown compression {compression!r}")

    def _unzstd(self, data: bytes, limit: int) -> bytes:
        proc = subprocess.Popen([self._zstd, "-q", "-d", "-c"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

        def feed() -> None:
            try:
                proc.stdin.write(data)
                proc.stdin.close()
            except OSError:
                pass

        feeder = threading.Thread(target=feed, daemon=True)
        feeder.start()
        out = proc.stdout.read(limit + 1)
        if len(out) > limit:
            proc.kill()
        proc.stdout.close()
        returncode = proc.wait()
        feeder.join()
        if len(out) > limit:
            raise ArchiveRejected("decompressed size exceeds the limit")
        if returncode != 0:
            raise ArchiveRejected("zstd stream unreadable")
        return out


def stamp_extracted(dest: Path, names: list[str], timestamp_ns: int | None = None) -> None:
    stamp = time.time_ns() if timestamp_ns is None else timestamp_ns
    nofollow = os.utime in os.supports_follow_symlinks
    for name in names:
        path = dest / name
        if path.is_symlink() and not nofollow:
            continue
        try:
            os.utime(path, ns=(stamp, stamp), **({"follow_symlinks": False} if nofollow else {}))
        except OSError:
            continue
