# 0016. Scale CI with an ephemeral runner pool and overflow to hosted runners

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: D3, D14, D17, D18 in docs/platform/requirements.md

## Context

The repository is public and owned by a personal account, so runners register per repository and a token with Administration permission is needed to mint just-in-time (JIT) configs (`scripts/proxmox/ephemeral/homelab-ephemeral-runner.sh:47`, `:79`). GitHub-hosted standard runners are free for public repositories (https://docs.github.com/en/billing/concepts/product-billing/github-actions).

Measured baselines (job-level data, 2026-10): hosted full suite, cold cache, 71 s (run 37355482969); the old self-hosted setup, 174 s (run 37341728563, second attempt), of which the Report job queued 64 s because the `dotnet` label had one runner.

Routing today picks hosted runners only for a forced override or a different repository (`.github/workflows/reusable-sdet-pipeline.yml:60-63`). A fork pull request runs in the base repository, so it lands on self-hosted runners; GitHub documents this at https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows. The host is attached to a VPN, a tailnet and the home LAN, so untrusted code must not run on long-lived runners there.

Scope note: whether the controller is built or adopted (D10) and in which language (D11) is still OPEN. This ADR does not decide it; it only states what any controller must do.

## Options considered

1. Fixed warm pool of long-lived runners — simple, but runners keep state between jobs, so untrusted code can persist; one label with one runner already queued a job for 64 s.
2. Hosted runners only (the laptop as baseline) — no isolation problem and no maintenance, but none of the speed or cache goals.
3. Ephemeral pool with a controller, overflow to hosted runners — a fresh runner per job, pool sized by queue depth, hosted as the safety net.

## Decision

Option 3, with these rules:

- Every self-hosted runner is JIT and ephemeral and is destroyed after one job (D3).
- When the pool is saturated, unavailable, the VM is stopped or the laptop is off, jobs overflow to hosted runners automatically (D14); the VM starts on demand, so a stopped VM counts as pool-not-ready.
- Fork pull requests always run on hosted runners; self-hosted runners run only the repository's own refs (D17). Runners also cannot reach private networks the host is attached to (two enforcement layers: Hyper-V port ACLs and a Windows firewall rule, `scripts/hyperv/README.md`).
- The laptop is the primary path and must beat hosted (D18). Targets, each held for 5 consecutive runs: full suite 60 s or less with warm caches; queue-to-start p95 10 s or less; scale from zero to job start 30 s or less; cache hit 95 percent or more on an unchanged lockfile.
- Queueing (R8): superseded runs on one ref are cancelled; priority is default branch, then pull request, then schedule; a job past its deadline overflows to hosted.

## Rationale and trade-offs

- Ephemeral runners remove persistence between jobs, which is what makes running public-repository code on this host defensible; hosted overflow keeps CI green when the laptop is off.
- Measured: the Proxmox VM answered SSH 18.1 s after `Start-VM` (#58). Runner boot adds to that and is unmeasured, so the 30 s scale-from-zero target is HYPOTHESIS until the load test. The targets are measured with the VM running.
- Accepted cost: a controller to build or adopt, a token with Administration scope, and a pool bounded by the VM's 12 vCPU and 20 GiB.
- Revisit D18 if the targets are not met after the optimization phase; the fallback is hosted as primary.
