from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass


class StoreUnavailable(Exception):
    pass


class WriteRefused(Exception):
    pass


class WriteFailed(Exception):
    pass


class ManifestError(ValueError):
    pass


class ArchiveRejected(Exception):
    pass


SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
KEY_RE = re.compile(r"^[a-z0-9_]+(-[a-z0-9_]+)*-[0-9a-f]{64}$")
COMPRESSIONS = ("zstd", "gzip")


@dataclass(frozen=True)
class Manifest:
    key: str
    kind: str
    sha256: str
    size: int
    compression: str

    def __post_init__(self) -> None:
        if not KEY_RE.match(self.key):
            raise ManifestError(f"malformed key: {self.key!r}")
        if not SHA256_RE.match(self.sha256):
            raise ManifestError(f"malformed blob digest: {self.sha256!r}")
        if self.compression not in COMPRESSIONS:
            raise ManifestError(f"unknown compression: {self.compression!r}")
        if not isinstance(self.size, int) or self.size < 0:
            raise ManifestError(f"malformed size: {self.size!r}")

    def to_json(self) -> str:
        return json.dumps(asdict(self), sort_keys=True)

    @staticmethod
    def from_json(text: str) -> "Manifest":
        try:
            raw = json.loads(text)
            return Manifest(
                key=raw["key"],
                kind=raw["kind"],
                sha256=raw["sha256"],
                size=raw["size"],
                compression=raw["compression"],
            )
        except (ValueError, KeyError, TypeError) as exc:
            if isinstance(exc, ManifestError):
                raise
            raise ManifestError(f"unreadable manifest: {exc}") from exc


@dataclass(frozen=True)
class Platform:
    runner_class: str
    os_id: str
    os_version: str
    arch: str
