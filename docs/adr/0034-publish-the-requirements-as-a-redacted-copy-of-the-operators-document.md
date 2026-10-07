# 0034. Publish the requirements as a redacted copy of the operator's document

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D61 in docs/platform/requirements.md

## Context

Recorded after the implementation, as a late record under the repository's rule that every decision gets an ADR. Implemented by #57 (branch `docs/platform-requirements`), which publishes `docs/platform/requirements.md`.

The requirements document that drives the platform was written by the operator on the operator's own machine. It names the host-routed prefixes, the private LAN and mesh addresses, the workstation and the user account, and it quotes local paths. The repository is public and must stay neutral and English-only, so the document cannot be committed as written. The decision log and the ADRs cite `docs/platform/requirements.md` by row, so a copy has to exist in the repository.

## Options considered

1. Publish the document as is — no drift, but it leaks the lab's addressing and identities into a public repository.
2. Publish a redacted copy produced by a sanitizing builder — repeatable, and the builder can refuse input it does not recognise.
3. Publish a hand-edited copy — no tooling, but every omission depends on the editor noticing it and nothing records what was changed.

## Decision

Option 2.

- `docs/platform/requirements.md` is a redacted copy of the operator's document. The sanitizing builder is kept with the operator notes and is not in the repository.
- Replaced with labels: the host-routed prefixes, the private LAN and mesh addresses, the workstation name and the user name.
- Removed: local paths.
- The unredacted document stays with the operator. Once #57 is merged, the repository copy is canonical.
- Deciding criterion: the repository is public and must stay neutral and English-only.

## Rationale and trade-offs

- The builder counts each substitution and aborts on a mismatch, so text it does not expect fails the build and is not published by default.
- Accepted loss: two copies can drift. The repository copy wins once merged, so later changes are made there and the operator's unredacted document is the one that has to catch up.
- Accepted loss: the builder is not in the repository, so a reviewer cannot re-run the redaction; review of #57 covers only the published text.
