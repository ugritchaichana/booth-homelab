# 0053. Prove Phase 4 on a runner-template clone before runners exist

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D80 in docs/platform/requirements.md

## Context

Phase 4 must show a cache hit ratio of at least 95% with an unchanged lockfile and a test that rebuilds sources changed in an earlier commit. Its stated proof is "hit and miss run URLs". No self-hosted runner exists before the Phase 5 controller, and the old runners are offline, so every self-hosted job of the repository waits in the queue. A run URL for a self-hosted hit cannot exist in this phase.

## Options considered

1. Wait for Phase 5 and measure the hit ratio only in real CI runs — the cache would ship unmeasured into the phase that depends on it.
2. Register a temporary runner by hand — it would bypass the Phase 5 entry gates (fork routing, ephemeral JIT runners, firewall read-back) for public-repository code.
3. Measure on a linked clone of the runner template, on the runner vnet with the runner firewall policy, driven from pve01 — the R15 probe clones of ADR 0044 — and run the stale-binary test in hosted CI, which needs no lab.

## Decision

Option 3. The probe clone runs the cache client exactly as a job would: a fresh checkout per iteration at the runner's workspace path, the runner user, the template's toolchains, the same keys and the same route to the cache. Twenty iterations measure the hit ratio by two instruments, the client's own stats and the server's access log. The stale-binary test runs in the repository's hosted cache CI with .NET SDK 8.

## Consequences

- The hit ratio (rows 63, 70) and the bad and edge paths (row 65) are measured on this laptop; the stale-binary result (row 64) has a CI run.
- The probe clone's default size (1 core, 256 MB) cannot build the solution; it was resized to 4 cores and 4 GiB for the measurement, which a real runner flavor must also provide.
- A hit-ratio run URL from real CI is owed by Phase 5, whose load test must meet the same Q7 target.
