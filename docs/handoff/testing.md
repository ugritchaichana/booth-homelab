# Testing

The row-by-row catalogue is [test-catalogue.md](../knowledge/test-catalogue.md): one row per test file, what it proves (happy, bad and edge paths), the local command, the CI job, and where only the host proves the claim. This page summarizes it by suite and states what a green CI run does not prove.

## Principle

Fakes prove logic, not the host's contracts. Phases 2-4 were built against fakes and disposable containers, then run once on the real host; every defect in [real-host-defects.md](../knowledge/real-host-defects.md) was found only by that run (permission checks that depend on pool context, command surfaces that differ from documentation, lagging listings, inherited clone state, first-boot services). Where a defect could be modelled offline, the fix added a test or fake behaviour for it. Two rules apply to new tests: a check that has never run red proves nothing, and a block without a paired control proves nothing (ADR 0031).

## Suites

| Suite | Count and location | What it proves | Runs in |
|---|---|---|---|
| Isolation and host-role shell tests | 16 files, `tests/isolation/test-*.sh` | Rendering of the cluster firewall and the guard's accept and reject sets; the template orchestrator against a fake `pvesh`/`qm`/`pct` (build, retention, lock, rollback, refusal of low storage, symlink in the work directory); the sandboxed guest step and the in-guest seal; unit sandbox rules; template content lint (every artifact pinned by hash); API-identity grants (`VM.Clone` only on the templates pool); R15 probe row logic including red-first and cache rows; cache service role, start gate, address wait, blob sweep, writer-secret script (with mutants that must fail) | Hosted CI, Ansible job |
| OpenTofu tests | 6 `*.tftest.hcl` files under `iac/tofu/stacks/*/tests/` | Flavor catalog sizes (`aws/t3.medium` is 2 cores, 4096 MB, 30 GB); SDN overlap and range rejections; a second host plans with no code change; clones inherit the template firewall and the stack declares none; template resolution refuses zero, two, non-template, outside-pool, outside-block and unknown-class matches; the cache container's shape and firewall | Hosted CI, OpenTofu job |
| Molecule | 1 scenario, role `base` | The baseline role converges in a Debian 13 systemd container, a second run changes nothing, sshd settings, dead-man unit, key-only account, root key restriction and time sync hold | Hosted CI |
| Cache client | 7 Python files under `tests/cache/` plus `test_stale_binaries.sh` | Key stability and sensitivity; save and restore round trips; refusal of traversal, absolute, link and device members, digest mismatches, bad pointers, decompression bombs and old interpreters; HTTP store behaviour against 401, 404, 500 and unreachable servers; CLI policy (no save on a non-default ref, no save after a verified hit); layering (a domain module importing an adapter is caught); the workflow keeps the writer secret in save-step environments only and rejects the `cond && '' \|\| url` shape | Cache client CI |
| Stale-binary test | `tests/cache/test_stale_binaries.sh`, hosted, .NET SDK 8 | Red on the stale variant, green on the new design, hit on an unchanged tree with `CoreCompile` skipped 7 of 7 | Cache client CI; run 37592628530 (row 64) |
| Affected-graph selector | `tests/verify-affected-graph.sh` and `.ps1` | Exact-set selection in seven (shell) and six (PowerShell) scenarios; three mutants each fail a named scenario | Hosted CI |
| Evidence publisher | `tests/evidence/test_publish.py` | Exact-value substitution never cuts a longer address or a version string; every checker rule is red on a crafted line; `--check` prints `file:line:rule` and never the matched text | Hosted CI |

CI workflows: `iac-ci.yml` (OpenTofu job and Ansible job), `cache-ci.yml`, `evidence-ci.yml`, `affected-selector-ci.yml`, `secret-scan.yml`. IaC CI was green at the head of every phase 2 chain pull request (row 54) and the catalog tests ran in run 37560039041 (row 60).

The catalogue does not list `tests/cache/test_extraction_limits.py` and `tests/cache/test_workflow_secrets.py` as rows; their behaviour is described from the files and row 70.

## Host-only proofs

These cannot be made by hosted CI; the transcript on the real host is the proof (see each phase index).

| Claim | Where it was proven | Evidence |
|---|---|---|
| Isolation from inside runner-class guests, including red-first and after reboots | `iac/ansible/playbooks/r15-verify.yml` running `tests/isolation/r15-probe.sh` in the probe clones | [phase 2](../evidence/phase2/INDEX.md), [phase 3](../evidence/phase3/INDEX.md), [phase 4](../evidence/phase4/INDEX.md); rows 51, 52, 59, 66 |
| Switch ACL shapes, Windows-side paired controls | `scripts/hyperv/Test-R15Controls.ps1`, elevated runs | [phase 1](../evidence/phase1/INDEX.md), [controls after host reboot](../evidence/phase2/controls-after-host-reboot.txt); rows 37, 42 |
| Token 403 and 200 outcomes, the clone's inherited tags and firewall | Live API on pve01 | rows 48, 57, 58; [proof-rollback-token.txt](../evidence/phase3/proof-rollback-token.txt) |
| SDN zone, vnet and SNAT exist and behave | Host stack apply and plan | rows 50, 61; [tofu-proxmox-host-final-plan.txt](../evidence/phase4/tofu-proxmox-host-final-plan.txt) |
| Template builds, retention, rollback, timer firing, manifest hashes | Both classes built six times | rows 55, 56; [phase 3 index](../evidence/phase3/INDEX.md) |
| Docker works in the VM class and exposes no TCP listener or virtualization flags | A clone of `vm-docker` | row 59; [evidence-vm-clone.txt](../evidence/phase3/evidence-vm-clone.txt) |
| Cache API contract, eviction, crash and reboot behaviour, hit ratio over 20 runs | `cache01` and a runner clone | rows 62-67; [phase 4 index](../evidence/phase4/INDEX.md) |
| Converge idempotency on the real host (`changed=0`) | Ansible runs against pve01 | rows 43, 46, 60; [phase 2 index](../evidence/phase2/INDEX.md) |
| In-role assertions during a converge | `roles/pve_firewall/tasks/verify.yml`, `pve_templates/tasks/assert.yml`, `pve_api_identity/tasks/assert.yml` | [phase 3 converge](../evidence/phase3/converge-site-1.txt) |

## What a green CI run does not prove

- That any rule works on a real firewall, any token has the privileges the tests assume, or any container survives a reboot.
- That a self-hosted job runs: no runner of the new platform exists, so the self-hosted path of the pipeline has never executed (row 68).
- Performance: the 71 s and 174 s baselines (rows 15, 16) have no new-platform counterpart yet ([results.md](results.md)).

## Running the local checks

Use the operator toolchain from the repository root. The command per file is in the catalogue; the shell tests take no argument and exit non-zero on the first broken expectation; OpenTofu tests need `tofu init -backend=false` and a throwaway state passphrase of 32 or more characters; the evidence check is `publish.py --check docs/evidence docs/knowledge` ([knowledge README](../knowledge/README.md)). Runbook 4.1 "Offline suites (no host)" lists the host-free checks and 4.2 "Host proofs (real host)" the host ones.
