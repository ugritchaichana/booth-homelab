# 0002. Keep the repository neutral and English-only

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: R16 in docs/platform/requirements.md

## Context

The owner intends this repository as a homelab baseline "that can be taken in any direction" and will adapt it later. Anything that names an employer, an organization, a team, a person, or an AI vendor ties the baseline to one context and has to be stripped before a fork. Part of the earlier content was also not in English.

A deny-list scan on 2026-10-06 found existing hits in the agent-context file, a vendor-named agent guide, one wiki page, and in the open scorecard pull request. They are tracked under R16 and are not all cleaned up on every branch; this record sets the rule they are measured against.

## Options considered

1. Neutral and English-only, enforced by a deny-list scan — a fork inherits nothing to scrub; the scan needs its patterns kept somewhere private.
2. Neutral by convention, no scan — no tooling; names reappear unnoticed, especially in pull request bodies and logs.
3. Keep context-specific names and let each fork rewrite them — least work now; every adopter repeats the cleanup and risks publishing something private.

## Decision

The repository, its documentation, pull request bodies and commit messages name no employer, organization, team, person, or AI vendor. Attribution is "owner" or "operator". Every artifact is in English. Identity rules are generic: never commit with a work identity. A deny-list grep must return no lines over the tree, the open branches and the pull request bodies; the patterns are kept outside the repository, because a list of the forbidden names is itself such a list.

## Rationale and trade-offs

- A deny-list grep is mechanical. It is the enforcement: the commits for the host work added no hit to the tree, the branches or the pull request bodies (neutrality scan recorded in #58). Closing the pre-existing hits is tracked separately under R16.
- The same rule covers measured data: host addresses, host names, fingerprints and secrets are written as labels (for example "the home LAN", "a host VPN"), while the lab ranges that already appear in configuration (`10.99.0.0/24`) are allowed.
- Accepted cost: reports are less specific than a private log would be. The specifics stay in the operator's local notes, which are not part of the repository.
- Residual gap: the scan catches names it knows. A new name in a new form is caught only by review.
- Revisit if the owner changes the intended audience of the repository.
