# 0052. Publish sanitized evidence and knowledge in the repository

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D81 in docs/platform/requirements.md

## Context

Release requirement R20 asks the repository to hold the platform's measured results and what was learned, not only its code. The measurements are transcripts of runs on the real host: Ansible and OpenTofu output, firewall and guard journals, isolation probe results, cache loop results. Their raw form carries values that must not be published: addresses of the operator's networks and machines, machine and user names, home paths and the names of the operator's tooling directories. ADR 0002 keeps the repository neutral and English-only, and ADR 0034 already publishes the requirements as a redacted copy of the operator's document.

Facts that decide the design:

- Some published files are hash-anchored: the template manifests are hashed and the hash is recorded in each template's description, so one changed byte breaks the anchor.
- A pattern-based IPv4 mask once rewrote part of a package version string (a dotted four-part number inside a version) and produced a false hash mismatch. A mask that guesses can change the evidence it protects.
- A check that only knows the values it was given misses what it was not given: the first exact-value map missed a user name that follows a backslash and a word inside a quoted command line, and an independent scan found both after the files were already committed locally.
- Several things that look like leaks are not: systemd unit names contain an at sign, reverse-DNS names end in `.arpa`, and the role defaults already published in the repository print the same documentation and test addresses back in a converge log.

## Options considered

1. Keep the evidence outside the repository, with the operator — nothing can leak, but the requirements point at files nobody else can read, the claims cannot be checked, and the knowledge disappears with the workstation.
2. Publish the raw transcripts — complete and checkable, but it publishes real addresses, machine and user names and home paths. Rejected.
3. Mask by pattern (any IPv4 address, any user path) — needs no operator input, but a pattern cannot tell an address from a version string and it rewrites evidence on a guess. Rejected after it altered a version string.
4. Substitute exact values from an operator-local map and check the result with a checker that flags and never rewrites — the substitution is reproducible and the checker catches what the map does not know.

## Decision

Option 4, implemented by `scripts/evidence/publish.py`, with selection files `scripts/evidence/selection-phase<N>.json` naming each file, its destination under `docs/evidence/<phase>/` and the one claim it backs.

- Substitution is by exact value only, in one pass, longest value first. The value map lives with the operator and is never committed; a value shaped like an address is not cut out of a longer dotted number. Counts of substitutions are recorded per label family in each phase's `INDEX.md`, never the values.
- The checker flags and never rewrites. Hard rules: an IPv4 address outside the lab range and the allowlist, a Windows user path, an email address, a tailnet domain, a private-key header, an age secret key prefix, a PVE API token with a value, a GitHub token prefix, a Thai character, a path segment naming the operator's tooling directory, and the credential-mask marker. It prints `file:line:rule` and never the matched text. A file with a hard flag is withheld and the run fails; the operator extends the map or justifies an allow entry and runs the same command again. Version-like tokens and non-ASCII characters are soft: listed, not failing.
- Precision is by evidence, not by relaxation: systemd unit names and `.arpa` names are not emails; an address already present in a git-tracked file under a named directory (never the secrets directory) is already public in the repository; an address may be allowed one by one in `scripts/evidence/allowed-addresses.txt`, each with a required reason. Each rule keeps firing on its true positives and has a unit test and a mutation.
- Hash-anchored files are published byte-identical or withheld: a file that needs even one substitution is recorded in the index as withheld with the sha256 of the original, never published modified.
- The operator keeps a deny-list of words that must never appear. `--deny-list <file>` makes any case-insensitive occurrence a hard flag. The list is read from the operator's machine and is never committed, so CI runs without it; the local run is the gate for it.
- A credential mask runs on every file after substitution; any mask marker in the output stops that file.
- CI runs the unit tests and `publish.py --check docs/evidence docs/knowledge` with the tracked-address sources `iac` and `tests` on pull requests that touch these paths.
- The same directory holds knowledge pages in `docs/knowledge/`: the defects only the real host exposed, and the test catalogue, each linking the evidence index rather than a local path.

## Rationale and trade-offs

- The map is the single place that knows what is private. A reviewer can trust a published file because the checker says what is absent, and an operator can repeat the run from the selection files without a person in the loop.
- Exact-value substitution costs an operator step when a new value appears. That is the intended cost: a miss is a withheld file and a visible flag, not a silent change.
- The map and the deny-list are operator-local, so CI cannot detect a value only they know. The checker therefore covers shape (addresses, paths, tokens, domains) and the operator-local run covers values and words. An independent by-value scan of the published files found two leaks the shape rules could not see; that is the reason the deny-list rule and the tooling-directory rule exist.
- Allowing addresses that are already tracked means a leaked address that is later committed under `iac` or `tests` also becomes allowed in evidence. Review of that commit, and the secret scan, are the control for it.
- Evidence that needs an operator-local map cannot be regenerated by someone else; the published copy and its hashes are the record.
