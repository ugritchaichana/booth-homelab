from __future__ import annotations

import hashlib
import logging
import time
from pathlib import Path
from typing import Sequence

from ..domain.models import BadRequest, Manifest, WriteFailed, WriteRefused
from ..domain.policy import WriteDecision
from .ports import STORE_FAILURES, Archiver, Outcome, Store

log = logging.getLogger("build_cache")


def save(
    kind: str,
    key: str,
    source_root: Path,
    paths: Sequence[str],
    store: Store,
    archiver: Archiver,
    decision: WriteDecision,
    restored_verified_hit: bool = False,
) -> Outcome:
    started = time.monotonic_ns()

    def outcome(status: str, nbytes: int = 0, detail: str = "") -> Outcome:
        ms = (time.monotonic_ns() - started) // 1_000_000
        log.info("save %s %s: %s %s", kind, key[-12:], status, detail)
        return Outcome("save", kind, key, status, nbytes, ms, detail)

    if not decision.allowed:
        return outcome("skipped", detail=decision.reason)
    if restored_verified_hit:
        return outcome("exists", detail="this job restored the key and verified the blob")

    packed = archiver.pack(source_root, paths)
    if packed is None:
        return outcome("empty", detail="nothing to archive")
    sha = hashlib.sha256(packed.data).hexdigest()
    manifest = Manifest(key=key, kind=kind, sha256=sha, size=len(packed.data), compression=packed.compression)
    try:
        store.put_blob(sha, packed.data)
        store.put_pointer(key, manifest)
    except WriteRefused as exc:
        return outcome("refused", len(packed.data), str(exc))
    except BadRequest as exc:
        return outcome("error", len(packed.data), f"bad request, client bug: {exc}")
    except WriteFailed as exc:
        return outcome("failed", len(packed.data), str(exc))
    except STORE_FAILURES as exc:
        return outcome("unreachable", len(packed.data), str(exc))
    return outcome("saved", len(packed.data))
