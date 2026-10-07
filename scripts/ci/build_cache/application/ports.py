from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Protocol, Sequence

from ..domain.models import Manifest, StoreUnavailable
from ..domain.policy import ExtractionRules


@dataclass(frozen=True)
class Packed:
    data: bytes
    compression: str


class Store(Protocol):
    def get_pointer(self, key: str) -> Manifest | None: ...

    def put_pointer(self, key: str, manifest: Manifest) -> None: ...

    def get_blob(self, sha256: str) -> bytes | None: ...

    def put_blob(self, sha256: str, data: bytes) -> None: ...


class Archiver(Protocol):
    def pack(self, root: Path, paths: Sequence[str]) -> Packed | None: ...

    def unpack(self, data: bytes, compression: str, root: Path, rules: ExtractionRules) -> list[str]: ...


STORE_FAILURES = (StoreUnavailable, OSError, TimeoutError)


@dataclass(frozen=True)
class Outcome:
    op: str
    kind: str
    key: str
    status: str
    bytes: int
    ms: int
    detail: str = ""

    def as_record(self) -> dict[str, object]:
        return {
            "op": self.op,
            "kind": self.kind,
            "key": self.key[-64:][:12],
            "status": self.status,
            "bytes": self.bytes,
            "ms": self.ms,
            "detail": self.detail,
        }
