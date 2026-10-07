from __future__ import annotations

from dataclasses import dataclass


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
