# Handoff package

This directory hands a CI platform on Proxmox VE 9 to the team that will build it in production and continue it. The platform was built and measured on one workstation as a reference implementation, not as a production system ([R18](../platform/requirements.md)). The people who built it do not operate it.

How to read the citations: `row N` is row N of section 3 (Measured constraints) in [requirements.md](../platform/requirements.md); `DN` is a row of its decision log; `RN` is a requirement; `ADR NNNN` links to the record; evidence files are linked directly. A claim without one of these is an opinion and says so.

## Status in one table

| Phases | State | Proof |
|---|---|---|
| 0 Requirements | Agreed 2026-10-06 | requirements.md header, R12 |
| 1 Machine and hypervisor | Done | rows 35, 36, 40; [phase 1 index](../evidence/phase1/INDEX.md) |
| 2 IaC foundation and isolation (R15) | Done | rows 41-54; [phase 2 index](../evidence/phase2/INDEX.md) |
| 3 Golden templates and regeneration | Done | rows 55-60; [phase 3 index](../evidence/phase3/INDEX.md) |
| 4 Build cache | Done | rows 61-70; [phase 4 index](../evidence/phase4/INDEX.md) |
| 5 Runner pool controller | Not started; entry gates written | [next-phases.md](next-phases.md) |
| 6 Workflow cutover | Not started | [next-phases.md](next-phases.md) |
| 7 Observability, backups, drills | Not started | [next-phases.md](next-phases.md) |
| 8 Rebuild-from-zero runbook and portability | Not started | [next-phases.md](next-phases.md) |

Phases 2, 3 and 4 each passed an independent audit against their DONE WHEN clause (requirements.md section 5, Phase 2, 3 and 4 status lines). The release scope was cut after Phase 4 by the owner (requirements.md change log, 2026-10-07).

## What is built and proven

| Component | What exists | Proof |
|---|---|---|
| Host layer (Windows only) | Hyper-V VM with nested virtualization, internal switch plus NAT, 18 switch port ACLs, a Windows firewall rule, restore points taken only while the VM is off | rows 35, 36, 40, 42, 45, 53; ADR 0003, 0006, 0007, 0019 |
| Host baseline | Unattended PVE 9.1 install, no-subscription upgrade through Ansible, key-only automation user, hardened sshd behind a dead-man timer, `hv_sock` blocked | rows 41, 43, 46, 47; ADR 0004, 0005, 0023, 0028 |
| Identity and secrets | OpenTofu API identity bootstrapped by Ansible, one SOPS file per consumer, encrypted OpenTofu state | rows 48, 49; ADR 0009, 0026, 0033, 0013 |
| Firewall and guard | Cluster firewall groups, per-vnet guard that stops non-compliant guests | rows 47, 61; ADR 0027, 0037, 0047 |
| Guest networks | Simple SDN zone with two isolated, source-NATed vnets (runners, cache) | rows 50, 61; ADR 0030, 0045 |
| Isolation proof (R15) | Red-first probe from runner-class guests, 19 negatives and 2 positives per runner clone, repeated after container, PVE and laptop reboots | rows 51, 52, 59, 66; ADR 0031 |
| Golden templates | Two classes (`lxc-runner`, `vm-docker`), versioned, two kept, one-command rollback, weekly rebuild | rows 55-60; ADR 0038-0044 |
| Build cache | bazel-remote container, content-keyed client, anonymous reads, one writer credential, LRU eviction | rows 62-65, 67, 70; ADR 0048-0050 |
| Workflows | Reusable pipeline with the cache wiring, green on the hosted fallback with the cache disabled; stale-binary test red-first | rows 64, 68; ADR 0049 |
| Evidence and knowledge | Sanitized transcripts per phase with hash indexes, defect list, test catalogue | row 69; ADR 0052; [knowledge](../knowledge/README.md) |

## What is not built

- The runner pool controller, JIT ephemeral runners, scaling, queueing and overflow (Phase 5). No runner of the new platform exists, so no job has run on it.
- The cutover of the repository's workflows to the new pools and the deregistration of the old runners (Phase 6).
- Metrics, alerts, backups to another device, timed restore and drills (Phase 7).
- A rebuild from zero timed against the runbook, and a run on a non-Proxmox host (Phase 8).
- Every item named in [limits-and-gaps.md](limits-and-gaps.md).

The speed goal (faster than the 71 s hosted baseline, row 15) is therefore not yet measured on the new platform; see [results.md](results.md).

## Reading order

1. This file, then [architecture.md](architecture.md) and [security-model.md](security-model.md).
2. [limits-and-gaps.md](limits-and-gaps.md): what is open and what closes it.
3. [decisions.md](decisions.md) and the [ADR index](../adr/README.md).
4. [build-from-zero.md](build-from-zero.md), then [operations.md](operations.md).
5. [testing.md](testing.md) and [results.md](results.md).
6. [porting.md](porting.md) if the target is bare-metal Proxmox, then [next-phases.md](next-phases.md).

Source documents: [requirements.md](../platform/requirements.md) (R1-R20, rows 1-70, D1-D81, plan), [RUNBOOK.md](../../RUNBOOK.md), [real-host defects](../knowledge/real-host-defects.md), [test catalogue](../knowledge/test-catalogue.md).

## Who does what

| Role | Does |
|---|---|
| Technical lead of the receiving team | Owns the plan, approves design decisions and the Phase 5 entry gates, decides where the platform runs |
| Repository administrator (called "the owner" in the source documents) | Merges, sets GitHub settings and environment policies, creates fine-grained tokens, gives the go to deregister old runners |
| Operator | Runs the scripts, playbooks and OpenTofu from the operator toolchain (WSL on the reference setup), keeps the evidence |
| Host administrator | Accepts the elevation prompt and reboots on the Windows host; absent on bare metal |
| Reviewer | Reads every change before the repository administrator merges; the operator never merges (R11) |

## Rules that carry over

- Every claim in a document links to a raw log, a run or a decision; measured and hypothesized statements are labelled (R18, R20).
- Never narrow a check, unskip a test or soft-fail to go faster: speed is bought only without a false green (requirements.md section 8, text above the `P` row).
- The repository stays neutral and English-only; an adopter maps it to their environment in a fork (R16, R18, ADR 0002).
- A reference run's secrets are not reusable: the SOPS files are encrypted to the reference operator's key, so the receiving team generates every value again (R13; see [build-from-zero.md](build-from-zero.md)).
