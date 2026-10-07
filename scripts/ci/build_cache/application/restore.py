from __future__ import annotations

import hashlib
import logging
import os
import time
from pathlib import Path
from typing import Callable

from ..domain.models import ArchiveRejected, BadRequest, ManifestError, UnsafeRuntime
from ..domain.policy import ExtractionRules
from .ports import STORE_FAILURES, Archiver, Outcome, Store

log = logging.getLogger("build_cache")

OnExtracted = Callable[[list[str]], None]


def restore(
    kind: str,
    key: str,
    dest: Path,
    store: Store,
    archiver: Archiver,
    on_extracted: OnExtracted | None = None,
    rules: ExtractionRules = ExtractionRules(),
) -> Outcome:
    started = time.monotonic_ns()

    def outcome(status: str, nbytes: int = 0, detail: str = "") -> Outcome:
        ms = (time.monotonic_ns() - started) // 1_000_000
        log.info("restore %s %s: %s %s", kind, key[-12:], status, detail)
        return Outcome("restore", kind, key, status, nbytes, ms, detail)

    try:
        manifest = store.get_pointer(key)
    except ManifestError as exc:
        return outcome("rejected", detail=f"unreadable pointer: {exc}")
    except BadRequest as exc:
        return outcome("error", detail=f"bad request, client bug: {exc}")
    except STORE_FAILURES as exc:
        return outcome("miss", detail=f"store unreachable: {exc}")
    if manifest is None:
        return outcome("miss", detail="no pointer for this exact key")
    if manifest.key != key or manifest.kind != kind:
        return outcome("rejected", detail="pointer does not describe the requested key")

    try:
        blob = store.get_blob(manifest.sha256)
    except BadRequest as exc:
        return outcome("error", detail=f"bad request, client bug: {exc}")
    except STORE_FAILURES as exc:
        return outcome("miss", detail=f"store unreachable: {exc}")
    if blob is None:
        return outcome("miss", detail="blob evicted: the pointer names a blob the store no longer holds")
    actual = hashlib.sha256(blob).hexdigest()
    if len(blob) != manifest.size or actual != manifest.sha256:
        return outcome("rejected", len(blob), f"blob digest {actual[:12]} != manifest {manifest.sha256[:12]}")

    try:
        names = archiver.unpack(blob, manifest.compression, dest, rules)
    except UnsafeRuntime as exc:
        return outcome("error", len(blob), f"extraction refused: {exc}")
    except ArchiveRejected as exc:
        return outcome("rejected", len(blob), f"archive refused: {exc}")
    except OSError as exc:
        return outcome("rejected", len(blob), f"extraction failed: {exc}")
    if on_extracted is not None:
        on_extracted(names)
    return outcome("hit", len(blob))


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
