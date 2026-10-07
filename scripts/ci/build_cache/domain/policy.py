from __future__ import annotations

from dataclasses import dataclass
from pathlib import PurePosixPath


@dataclass(frozen=True)
class WriteDecision:
    allowed: bool
    reason: str


def write_decision(
    writer_credential_present: bool,
    event_name: str,
    ref: str,
    default_branch: str,
) -> WriteDecision:
    if not writer_credential_present:
        return WriteDecision(False, "no writer credential")
    if event_name != "push":
        return WriteDecision(False, f"event {event_name or '(none)'} is not a push")
    if ref != f"refs/heads/{default_branch}":
        return WriteDecision(False, f"ref {ref or '(none)'} is not the default branch")
    return WriteDecision(True, "push to the default branch with a writer credential")


DEFAULT_MAX_BYTES = 4 << 30
DEFAULT_MAX_MEMBERS = 1_000_000
MIN_PYTHON = {(3, 11): 13, (3, 12): 11, (3, 13): 4}


@dataclass(frozen=True)
class ExtractionRules:
    prefixes: tuple[str, ...] = ()
    required_segments: frozenset[str] = frozenset()
    max_bytes: int = DEFAULT_MAX_BYTES
    max_members: int = DEFAULT_MAX_MEMBERS


def member_allowed(name: str, rules: ExtractionRules) -> bool:
    parts = tuple(part for part in PurePosixPath(name).parts if part != ".")
    if not parts:
        return False
    rest = parts
    if rules.prefixes:
        for prefix in rules.prefixes:
            wanted = tuple(part for part in PurePosixPath(prefix).parts if part != ".")
            if parts[: len(wanted)] == wanted:
                rest = parts[len(wanted):]
                break
        else:
            return False
    return not rules.required_segments or bool(rules.required_segments & set(rest))


def supports_safe_extraction(version: tuple[int, ...]) -> bool:
    major_minor = tuple(version[:2])
    if major_minor in MIN_PYTHON:
        return tuple(version[:3]) >= (*major_minor, MIN_PYTHON[major_minor])
    return major_minor > (3, 13)
