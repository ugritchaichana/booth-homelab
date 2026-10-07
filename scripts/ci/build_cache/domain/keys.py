from __future__ import annotations

import hashlib
import json
from typing import Mapping

from .models import Platform

SCHEMA = 1
DEPENDENCY_KINDS = ("nuget", "node_modules")
OUTPUT_KIND = "dotnet-outputs"
KINDS = DEPENDENCY_KINDS + (OUTPUT_KIND,)


def digest(record: Mapping[str, object]) -> str:
    canonical = json.dumps(record, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
    return hashlib.sha256(canonical.encode("ascii")).hexdigest()


def _platform_record(platform: Platform) -> dict[str, str]:
    return {
        "runner_class": platform.runner_class,
        "os_id": platform.os_id,
        "os_version": platform.os_version,
        "arch": platform.arch,
    }


def _sorted_pairs(mapping: Mapping[str, str]) -> list[list[str]]:
    return [[path, mapping[path]] for path in sorted(mapping)]


def dependency_key(
    namespace: str,
    platform: Platform,
    toolchain_version: str,
    lockfile_sha256: Mapping[str, str],
) -> str:
    if namespace not in DEPENDENCY_KINDS:
        raise ValueError(f"not a dependency namespace: {namespace!r}")
    if not lockfile_sha256:
        raise ValueError("a dependency key needs at least one lockfile")
    record = {
        "schema": SCHEMA,
        "namespace": namespace,
        "platform": _platform_record(platform),
        "toolchain": toolchain_version,
        "lockfiles": _sorted_pairs(lockfile_sha256),
    }
    return f"{namespace}-{digest(record)}"


def outputs_key(
    platform: Platform,
    sdk_version: str,
    configuration: str,
    tree_ids: Mapping[str, str],
) -> str:
    if not tree_ids:
        raise ValueError("an output key needs at least one input tree id")
    record = {
        "schema": SCHEMA,
        "namespace": OUTPUT_KIND,
        "platform": _platform_record(platform),
        "toolchain": sdk_version,
        "configuration": configuration,
        "trees": _sorted_pairs(tree_ids),
    }
    return f"{OUTPUT_KIND}-{digest(record)}"
