# Testing

The file-by-file catalogue is [test-catalogue.md](../knowledge/test-catalogue.md): what each test proves (happy, bad and edge paths), its command and CI job, and where only the host proves the claim. This page summarizes it by suite and states what a green CI run does not prove.

## Principle

Fakes prove logic, not the host's contracts. Phases 2-4 were built against fakes and disposable containers, then run once on the real host; every defect in [real-host-defects.md](../knowledge/real-host-defects.md) was found only by that run (permission checks that depend on pool context, command surfaces that differ from documentation, lagging listings, inherited clone state, first-boot services). Where a defect could be modelled offline, the fix added a test or fake behaviour for it. Two rules apply to new tests: a check that has never run red proves nothing, and a block without a paired control proves nothing (ADR 0031). A new test gets a catalogue row.

## Suites

| Suite | Location | What it proves | Runs in |
|---|---|---|---|
| Isolation, role and host-script shell tests | `tests/isolation/test-*.sh` | Rendering of the cluster firewall and the guard's accept and reject sets; the template orchestrator against a fake `pvesh`/`qm`/`pct` (build, retention, lock, rollback, refusal of low storage); the sandboxed guest step and the in-guest seal; unit sandbox rules; template content lint (every artifact pinned by hash); API-identity grants; R15 probe row logic including red-first and cache rows; cache service role, start gate, address wait, blob sweep, writer-secret script; roles `pve_host` and `hyperv_guest` run with fake modules, including their guards; the guest wrapper `new-guest.sh`; the SSH config renderer | `iac-ci.yml`, Ansible job |
| OpenTofu tests | `iac/tofu/stacks/*/tests/*.tftest.hcl` | Flavor catalog sizes (`aws/t3.medium` is 2 cores, 4096 MB, 30 GB); SDN overlap and range rejections; a second host plans with no code change; template resolution refuses zero, two, non-template, outside-pool, outside-block and unknown-class matches; the cache container's shape and firewall; the guest stack's naming, tags, slots, flavor budget and disk rules | `iac-ci.yml`, OpenTofu job |
| Molecule | role `base` | The baseline role converges in a Debian 13 systemd container, a second run changes nothing, sshd settings, dead-man unit, key-only account and time sync hold | `iac-ci.yml` |
| Cache client | `tests/cache/` | Key stability and sensitivity; save and restore round trips; refusal of traversal, absolute, link and device members, digest mismatches, bad pointers, decompression bombs and old interpreters; HTTP store behaviour against 401, 404, 500 and unreachable servers; CLI policy; environment detection; layering and I/O rules for the domain and application layers; the workflow keeps the writer secret in save-step environments only; every tar extraction in the reusable pipeline follows a member check | `cache-ci.yml` |
| Stale-binary test | `tests/cache/test_stale_binaries.sh` | Red on the stale variant, green on the new design, a hit skips `CoreCompile` for every project (row 64, stale-binary test) | `cache-ci.yml` |
| Hyper-V module | `tests/hyperv/*.Tests.ps1` (Pester) | Port-ACL planning and read-back, fail-closed egress selection, refusal of foreign ACLs, exit codes, checkpoint refused while running, duplicate name refused, configuration rejections, path and rights checks | `hyperv-ci.yml`, Windows PowerShell and pwsh |
| Affected-graph selector | `tests/verify-affected-graph.sh` | Exact-set selection scenarios; each workflow mutant fails a named scenario | `affected-selector-ci.yml` |
| Evidence publisher | `tests/evidence/test_publish.py` | Exact-value substitution never cuts a longer address or a version string; every checker rule is red on a crafted line; `--check` prints `file:line:rule` and never the matched text | `evidence-ci.yml` |
| Scorecard | `standard/tests/` | The scorer, its checks and the ledger | `standard-scorecard.yml` |

Coverage numbers per suite, with their runs: [coverage.md](../knowledge/coverage.md). CI workflows: `iac-ci.yml`, `cache-ci.yml`, `evidence-ci.yml`, `affected-selector-ci.yml`, `hyperv-ci.yml`, `standard-scorecard.yml`, `secret-scan.yml`.

## Host-only proofs

These cannot be made by hosted CI; the transcript on the real host is the proof (see each phase index).

| Claim | Where it was proven | Evidence |
|---|---|---|
| Isolation from inside runner-class guests, including red-first and after reboots | `iac/ansible/playbooks/r15-verify.yml` running `tests/isolation/r15-probe.sh` in the probe clones | [phase 2](../evidence/phase2/INDEX.md), [phase 3](../evidence/phase3/INDEX.md), [phase 4](../evidence/phase4/INDEX.md); row 51 (red-first isolation), row 52 (per-guest isolation runs), row 59 (clone isolation), row 66 (R15 with the cache path) |
| Switch ACL shapes, Windows-side paired controls | `scripts/hyperv/Test-R15Controls.ps1`, elevated runs | [phase 1](../evidence/phase1/INDEX.md), [controls after host reboot](../evidence/phase2/controls-after-host-reboot.txt); row 37 (ACL shapes) and row 42 (ACLs after a reboot) |
| Token 403 and 200 outcomes, the clone's inherited tags and firewall | Live API on pve01 | row 48 (token boundary), row 57 (template protection), row 58 (clone inheritance); [proof-rollback-token.txt](../evidence/phase3/proof-rollback-token.txt) |
| SDN zone, vnet and SNAT exist and behave | Host stack apply and plan | row 50 (guest network) and row 61 (cache network); [tofu-proxmox-host-final-plan.txt](../evidence/phase4/tofu-proxmox-host-final-plan.txt) |
| Template builds, retention, rollback, timer firing, manifest hashes | Both classes built six times | row 55 (template build time) and row 56 (retention and rollback); [phase 3 index](../evidence/phase3/INDEX.md) |
| A flavor guest is created with the planned size, tags and name, and a second apply settles the plan | `scripts/iac/new-guest.sh --apply` on pve01 | [guest-lxc-verify.txt](../evidence/closeout/guest-lxc-verify.txt), [guest-lxc-apply2.txt](../evidence/closeout/guest-lxc-apply2.txt), [guest-apply-vm.txt](../evidence/closeout/guest-apply-vm.txt); ADR 0055 |
| Docker works in the VM class and exposes no TCP listener or virtualization flags | A clone of `vm-docker` | row 59 (clone isolation); [evidence-vm-clone.txt](../evidence/phase3/evidence-vm-clone.txt) |
| Cache API contract, eviction, crash and reboot behaviour, hit ratio over 20 runs | the cache container and a runner clone | rows 62 to 67 (Phase 4 measurements); [phase 4 index](../evidence/phase4/INDEX.md) |
| Converge idempotency on the real host (`changed=0`) | Ansible runs against pve01 | row 43 (converge run), row 46 (first converge), row 60 (idempotence held); [phase 2 index](../evidence/phase2/INDEX.md) |
| In-role assertions during a converge | `roles/pve_firewall/tasks/verify.yml`, `pve_templates/tasks/assert.yml`, `pve_api_identity/tasks/assert.yml` | [phase 3 converge](../evidence/phase3/converge-site-1.txt) |

## What a green CI run does not prove

- That any rule works on a real firewall, any token has the privileges the tests assume, or any container survives a reboot.
- That a self-hosted job runs: no runner of the new platform exists, so the self-hosted path of the pipeline has never executed (row 68, hosted run with the cache disabled).
- Performance: the hosted and old self-hosted baselines have no new-platform counterpart yet ([results.md](results.md)).
- That the Pester tests match real Hyper-V: they run against stubs of the Hyper-V cmdlets.

## Running the local checks

The commands are in [runbook 4.1](../../RUNBOOK.md), "Offline suites (no host)"; the host ones are in 4.2, "Host proofs (real host)".
