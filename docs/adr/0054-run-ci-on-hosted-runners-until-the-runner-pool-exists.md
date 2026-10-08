# 0054. Run CI on hosted runners until the runner pool exists

- Status: Accepted; superseded in part by [0060](0060-run-own-ci-on-one-persistent-runner-container-behind-a-job-start-guard.md) (the repository's own runs use the Proxmox runner when `CI_RUNNER` is `proxmox`)
- Date: 2026-10-07
- Deciders: operator
- Decision log: D82 in docs/platform/requirements.md

## Context

The reusable SDET pipeline routes the repository's own pushes and pull requests to the labels `self-hosted, linux, proxmox, dotnet|angular`. The two runners that served those labels belonged to the retired host; they are registered but offline. Every own-repository run therefore waits in the queue until GitHub drops it after 24 hours, and the last master run failed on that host's full disk (Angular checkout "No space left on device", run 37341728563). The runner pool controller that will serve these labels from the golden templates is Phase 5, which this release hands off.

The hosted path is proven with the new cache wiring: with `CACHE_URL` empty every restore reports `miss (no store configured)`, and the run is green (run 37602620111).

## Options considered

1. Keep the self-hosted default — master and pull-request CI would never finish until Phase 5.
2. Deregister the old runners so jobs fail fast — CI would still produce no result, and deregistering is an owner step reserved for the Phase 6 cutover.
3. Route the caller workflow to hosted runners by default (`force_ubuntu_runner` true on push and pull request, dispatch default true) and switch it back when the pool exists.

## Decision

Option 3, in `.github/workflows/sdet-ci.yml` only. The reusable pipeline keeps its self-hosted path and the cache wiring unchanged, so the Phase 5–6 work flips one input back.

## Consequences

- Every push and pull request gets a CI result again; the hosted runners are free for a public repository (requirements row 26).
- The build cache is not used by hosted jobs (by design, ADR 0050); hosted jobs run cold.
- The Phase 6 cutover must remove this override, with its own blast radius.
