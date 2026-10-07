# Handoff package

This directory hands a CI platform on Proxmox VE 9 to the team that will continue it. The platform was built and measured on one workstation as a learning and reference implementation, not as a production system (requirement R18, a handoff-ready deliverable). The people who built it do not operate it.

Citations: `row N` is row N of section 3 (Measured constraints) in [requirements.md](../platform/requirements.md); `DN` is a row of its decision log; `RN` is a requirement. Each is written with its topic, for example "row 55 (template build time)". A claim without a citation is an opinion and says so.

## Status

This table is the only copy of the phase status; every other page links here.

| Phase | State | Proof |
|---|---|---|
| 0 Requirements | Agreed 2026-10-06 | requirements.md header |
| 1 Machine and hypervisor | Done | [phase 1 index](../evidence/phase1/INDEX.md); row 35 (unattended install), row 36 (nested KVM works) |
| 2 IaC foundation and isolation | Done | [phase 2 index](../evidence/phase2/INDEX.md); row 49 (OpenTofu state), row 52 (isolation per guest) |
| 3 Golden templates and regeneration | Done | [phase 3 index](../evidence/phase3/INDEX.md); row 56 (retention and rollback) |
| 4 Build cache | Done | [phase 4 index](../evidence/phase4/INDEX.md); row 63 (hit ratio over 20 runs) |
| 5 Runner pool controller | Not started; entry gates written | [next-phases.md](next-phases.md) |
| 6 Workflow cutover | Not started | [next-phases.md](next-phases.md) |
| 7 Observability, backups, object storage, drills | Not started | [next-phases.md](next-phases.md) |
| 8 Rebuild-from-zero runbook and portability | Not started | [next-phases.md](next-phases.md) |

Phases 2, 3 and 4 each passed an independent audit against their DONE WHEN clause (requirements.md section 5). The close-out added flavor-sized guests, the Hyper-V and role tests and published coverage; they extend Phases 2 to 4 and are not a new phase. All lab machines stay running as evidence (decision D86, lab machines after the release; the on-demand stop of D21, VM start policy, is suspended).

## What is built and proven

| Component | What exists | Proof |
|---|---|---|
| Host layer (Windows only) | Hyper-V VM with nested virtualization, internal switch plus NAT, switch port ACLs, a Windows firewall rule, restore points only while the VM is off | ADR 0003, 0006, 0007, 0019; row 42 (ACL read-back after a reboot) |
| Host baseline | Unattended PVE 9.1 install, upgrade through Ansible, key-only automation user, sshd hardening behind a dead-man timer, `hv_sock` blocked | ADR 0004, 0005, 0023, 0028; row 47 (host baseline after reboots) |
| Identity and secrets | OpenTofu API identity bootstrapped by Ansible, one SOPS file per consumer, encrypted state | ADR 0009, 0013, 0026, 0033; row 48 (token boundary) |
| Firewall and guard | Cluster firewall groups; a per-vnet guard that stops non-compliant guests | ADR 0027, 0037, 0047 |
| Guest networks | Simple SDN zone with two isolated, source-NATed vnets (`guests`, `cache`) | ADR 0030, 0045; row 61 (cache network) |
| Isolation proof (R15) | Red-first probe from runner-class guests, repeated after container, PVE and laptop reboots | ADR 0031; row 66 (R15 with the cache path); counts in [results.md](results.md) |
| Golden templates | `lxc-runner` and `vm-docker`, versioned, two kept, one-command rollback, weekly rebuild | ADR 0038 to 0044 |
| Flavor guests | One command creates a guest sized by a cloud flavor, named `<role>-<class>-v<N>`; two demo guests run on `pve01` | ADR 0055; [examples.md](examples.md) |
| Build cache | bazel-remote container `build-cache-debian-13`, content-keyed client, anonymous reads, one writer credential, LRU eviction | ADR 0048 to 0050 |
| Workflows | Reusable pipeline with the cache wiring; green on hosted runners with the cache off | ADR 0049, 0054; row 68 (hosted run with the cache disabled) |
| Tests and coverage | Shell, OpenTofu, Python and Pester suites, one catalogue, published coverage | [test catalogue](../knowledge/test-catalogue.md), [coverage](../knowledge/coverage.md) |
| Evidence and knowledge | Sanitized transcripts per phase with hash indexes, a defect list | ADR 0052; [knowledge](../knowledge/README.md) |
| Scorecard | A 100-point standard scored weekly by CI | [standard/README.md](../../standard/README.md) |

## What is not built

- The runner pool controller, JIT ephemeral runners, scaling, queueing and overflow (Phase 5). No runner of the new platform exists, so no job has run on it.
- The cutover of the workflows to the new pools and the deregistration of the old runners (Phase 6).
- Metrics, alerts, backups to another device, general object storage, timed restore and drills (Phase 7).
- A rebuild from zero timed against the runbook, and a run on a non-Proxmox host (Phase 8).
- Every item in [limits-and-gaps.md](limits-and-gaps.md).

The speed goal (faster than the hosted baseline) is not measured on the new platform; see [results.md](results.md).

## Reading order

1. This file, then [architecture.md](architecture.md) and [security-model.md](security-model.md).
2. [limits-and-gaps.md](limits-and-gaps.md): what is open and what closes it.
3. [decisions.md](decisions.md) and the [ADR index](../adr/README.md).
4. [build-from-zero.md](build-from-zero.md), [examples.md](examples.md), then [operations.md](operations.md).
5. [testing.md](testing.md) and [results.md](results.md).
6. [porting.md](porting.md) for a bare-metal target, then [next-phases.md](next-phases.md).
7. [standard/README.md](../../standard/README.md) for the scorecard that scores all of it.

Sources: [requirements.md](../platform/requirements.md), [RUNBOOK.md](../../RUNBOOK.md), [real-host defects](../knowledge/real-host-defects.md), [test catalogue](../knowledge/test-catalogue.md).

## Who does what

| Role | Does |
|---|---|
| Technical lead of the receiving team | Owns the plan, approves design decisions and the Phase 5 entry gates, decides where the platform runs |
| Repository administrator (the "owner" in the source documents) | Merges, sets GitHub settings and environment policies, creates fine-grained tokens, gives the go to deregister old runners |
| Operator | Runs scripts, playbooks and OpenTofu from the operator toolchain (WSL on the reference setup), keeps the evidence |
| Host administrator | Accepts the elevation prompt and reboots on the Windows host; absent on bare metal |
| Reviewer | Reads every change before the repository administrator merges; the operator never merges |

## Rules that carry over

- Every claim links to a raw log, a run or a decision; measured and hypothesized statements are labelled.
- Never narrow a check, unskip a test or soft-fail to go faster.
- The repository stays neutral and English-only; an adopter maps it to their environment in a fork.
- The SOPS files are encrypted to the reference operator's key, so the receiving team generates every secret again ([build-from-zero.md](build-from-zero.md)).
