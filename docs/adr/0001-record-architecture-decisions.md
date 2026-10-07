# 0001. Record architecture decisions

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: R2, R9 in docs/platform/requirements.md

## Context

The owner asked on 2026-10-06 that every approach and tool choice records why it was chosen, so the repository can later be adapted to another host (VPS, on-premises) without rediscovering the reasoning. Requirement R9 states it as a pass condition: "Every architecture decision has an ADR".

Before this record, reasons lived in two places that do not travel with the code: an operator-local decision log (D1 to D45 with options and criteria) and pull request bodies (for example #58, which carries the measured install and isolation results). The decision log is the source of truth during the work, but it is not part of a fork. Reasons that are only in a pull request are hard to find once it is merged.

## Options considered

1. ADRs in the repository (`docs/adr/`), one file per decision — travels with every fork and is reviewed in the same pull request as the change; costs one short file per decision.
2. The decision log only (`docs/platform/requirements.md`) — already exists and is dense; one table row cannot hold options, measurements and trade-offs, and it mixes decided and open items.
3. A wiki page or tracker per decision — easy to browse; it lives outside the git history, so a fork loses it and a decision can drift from the code it explains.

## Decision

Keep Architecture Decision Records in `docs/adr/`, one decision per file, named `NNNN-<kebab-of-title>.md`, using the template in `docs/adr/README.md`. Each pull request that finalizes a decision adds its ADR. The decision log keeps the short row and links to the ADR; the ADR carries the options, the evidence and the trade-offs.

## Rationale and trade-offs

- A record next to the code is reviewed with the code and survives a fork, which is the stated reason for asking (R2, R9).
- Four-digit numbers, never reused, give a stable reference that a script comment or a pull request can cite.
- Accepted cost: each decision needs a short write-up. The template is capped at about 25 to 60 lines to keep that cost low.
- Decisions still open (the controller choice and its language) get no ADR until they are decided; an ADR records a decision, not a question.
- Revisit if records stop being written with the change that makes the decision (check at each phase close).
