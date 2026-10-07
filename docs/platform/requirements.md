# Platform v2 Requirements — a neutral homelab CI baseline on Proxmox VE 9

| | |
|---|---|
| Status | `AGREED` |
| Owner | repository owner (`ugritchaichana`) |
| Operator | an AI coding agent |
| Canonical copy | This file is the canonical copy of the platform-v2 requirements once merged. |
| Opened | 2026-10-06 |
| Last updated | 2026-10-06 |
| Target repo | `ugritchaichana/booth-homelab` |
| Links | [`standard/README.md`](../../standard/README.md) (#55) · PR #48–#56 · run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969) |
| Single goal | **This workstation runs Proxmox VE 9, rebuilt entirely from code, and runs the repo's CI on single-use runners that scale with the queue — faster than the 71 s hosted baseline, with no false green.** |

Document rules:
- **Never delete earlier content.** When a decision changes, mark it `SUPERSEDED` and append the new one.
- Every requirement and decision carries a date.
- The project is a **neutral homelab baseline**. It names no employer or organization, and its artifacts are in English (R16).

---

## 0. One-page summary

> A new CI platform on this laptop replaces the retired host: 16 requirements, 9 phases, 0 open blocking questions. Phase 1 starts on the owner's go.

| | |
|---|---|
| What | Proxmox VE 9 as a Hyper-V VM on the workstation, installed by script and automated installer. Everything else is code:<br>• templates sized by cloud flavor<br>• smart caching<br>• per-machine identities<br>• an ephemeral runner pool whose controller scales, queues and regenerates<br>• reusable per-node workflows<br>• observability and backups<br>• a reproducible runbook |
| Why now | The owner retired the old host: Proxmox VE 8.4 has been past end of security support since 2026-08-31, its runner disks filled, and its runners went offline. The owner also retired the previous agent; an AI coding agent is now the operator. The repo is meant to be a neutral baseline the owner can later adapt to any VPS, on-prem or other environment. |
| Done when | (1) A rebuild from zero, following only the runbook, reaches a green pipeline and is timed.<br>(2) The full suite on master meets the Q7 targets for 5 consecutive runs.<br>(3) Every runner reports `ephemeral: true`.<br>(4) The scorecard holds evidence for every criterion the phases touch. |
| Biggest risk | (1) The host routes 7 private prefixes over a VPN interface. If runners executing public-repo code reach those networks through the host's NAT, they reach networks they must never see (R15).<br>(2) Enabling Hyper-V may break WSL2 and Docker Desktop, which the owner uses daily.<br>(3) Nested KVM on the Ryzen 7 PRO 5850U is unproven. |
| Unknown before start | No blocking question is open. Two non-blocking unknowns are settled in Phase 1:<br>• the nested KVM result (smoke test)<br>• whether a Hyper-V checkpoint works for a VM with nested virtualization |

---

## 1. Requirements received

> The owner gave 16 directions on 2026-10-06:
> - move to this machine
> - reproducible
> - cloud-flavor templates
> - best-practice IaC
> - Proxmox baseline capabilities
> - reusable workflows
> - extreme optimization
> - clean architecture
> - portability
> - neutral, English-only artifacts

Requirements are appended as `R1`, `R2`, …; never insert in the middle and never renumber. Owner quotes are translated from Thai, with organization names removed at the owner's request (R16). Quotes that named a vendor are paraphrased in brackets.

### R1 — The platform moves to this machine (2026-10-06)

- **Raw request:** "Stop using Proxmox on the old machine. We will implement on this machine now, but check this machine's condition carefully first, because the disk seems small."
- **Restated:**
  - Proxmox VE 9 runs as a Hyper-V Generation 2 VM on the workstation, within the Q1 budget.
  - WSL2, Docker Desktop and the host's VPN clients keep working.
  - The old host is retired after cutover.
- **Passes when:**
  - `pveversion` inside the VM prints `pve-manager/9.`.
  - `Get-VM` shows 12 vCPU, 24 GiB static RAM and a 140 GiB maximum VHDX.
  - C: keeps at least 20 GiB free after installation, with an alert below that.
  - After the reboot, `wsl -l -v` still lists `docker-desktop` and Docker Desktop starts.
  - After cutover, `gh api repos/ugritchaichana/booth-homelab/actions/runners` lists neither `pve-runner-01` nor `pve-runner-angular`.

### R2 — Recorded knowledge and a reproducible runbook (2026-10-06)

- **Raw request:** "The goal is to record the knowledge gained, and make a runbook that can be repeated once the experiment succeeds."
- **Restated:**
  - Every successful step becomes code (script, OpenTofu or Ansible) or a runbook step with its expected output.
  - Owner-only steps (UAC prompts, reboots) are marked as such.
  - Lessons (traps, workarounds, measured numbers) go into repo docs and the operator's notes.
- **Passes when:**
  - A rebuild of a fresh VM, following only the runbook, reaches a green pipeline.
  - Its log has start and end timestamps and is stored as evidence for criterion 3.4.
  - Every runbook step is a command or script with an expected result.

### R3 — Templates sized by cloud instance flavor (2026-10-06)

- **Raw request:** "Make templates based on AWS machines."
- **Answer to the template question:** "Do option 2 (generic cloud flavors) in this project; I will adapt it to other baselines myself later."
- **Restated:**
  - Runners and services are cloned from golden templates built once.
  - Size (vCPU / RAM / disk) comes from a flavor name in a provider catalog (`iac/tofu/flavors.json`). Example: `aws/t3.medium` = 2 vCPU / 4 GiB / 30 GB.
  - Organization-specific runner classes are out of scope.
- **Passes when:**
  - A test asserts every catalog entry has positive `cores`, `memory_mb` and `disk_gb`.
  - `tofu plan -var 'flavor=aws/t3.medium'` shows 2 cores / 4096 MB.
  - Every template carries a version tag and a manifest of OS and toolchain versions.

### R4 — Best-practice IaC with OpenTofu + Ansible (2026-10-06)

- **Raw request:** "Use best-practice OpenTofu + Ansible first; add anything else as appropriate."
- **Restated:**
  - OpenTofu declares all infrastructure: VMs, CTs, templates, networks, storage, users, tokens, ACLs.
  - Ansible holds all OS and service configuration.
  - Idempotent, with remote state and locking, and pinned tool versions.
  - CI runs fmt / validate / tflint / ansible-lint and plan.
  - Extra tools (Packer, mise, SOPS, …) are added only with a reason recorded in the decision log.
- **Passes when:**
  - `tofu plan -detailed-exitcode` exits 0 after apply (criterion 2.3).
  - A second `ansible-playbook site.yml` run reports `changed=0` on every host.
  - IaC CI meets criterion 2.5 (a)(c)(d).
  - Imperative provisioning scripts are removed or reduced to thin wrappers (criterion 2.1(b)).

### R5 — Proxmox baseline capabilities (2026-10-06)

- **Raw request:** "This work becomes the baseline for Proxmox: managing several machines, caching, permissions per machine, scaling, regeneration and more. Adapting it elsewhere happens later, in a fork."
- **Restated:** five capabilities.
  - **R5.1 Several machines:** an inventory supports N ≥ 1 independent hosts. Adding a host is a data change, not a code change (Q4).
  - **R5.2 Caching:** see R8.
  - **R5.3 Per-machine permissions:**
    - Every machine and runner has its own least-privilege identity.
    - PVE API tokens are split by role (provisioner / controller / backup) and limited to paths.
    - Runners get per-job credentials only.
    - The cache writer is reachable only from trusted refs.
    - Automation never uses the root password.
  - **R5.4 Scaling:** see R8.
  - **R5.5 Regeneration:**
    - Templates rebuild automatically, on a schedule or on toolchain change.
    - Two versions are kept, and rollback is a one-variable switch.
    - Runners are recreated for every job.
    - Caches are re-warmed after invalidation.
- **Passes when:**
  - An inventory with a second (plan-only) host plans resources on both.
  - `pveum acl list` shows only scoped roles.
  - A negative test shows the controller token cannot act outside its scope.
  - A scheduled template build exists, with two template versions retained.
  - A runner's clone is gone after its job.

### R6 — Reusable workflows, clearly separated per node (2026-10-06)

- **Raw request:** "Workflows focus on being reusable, clearly separated per node, and called piece by piece."
- **Restated:**
  - Each CI unit is a reusable workflow (`workflow_call`) with typed inputs and outputs, bound to one runner class. Examples: `dotnet-build`, `dotnet-test`, `angular-test`, `cache-save`, `iac-validate`, `template-build`.
  - Caller workflows only compose units per event.
  - Runner classes are separate pools per workload type and share no queue.
- **Passes when:**
  - Every unit has `on: workflow_call`.
  - Callers contain only `uses:` compositions.
  - actionlint reports nothing.
  - The docs have a "unit → runner class" table.

### R7 — Extreme optimization (2026-10-06)

- **Raw request:** "This work is about extreme optimization, so whatever can reduce time, we reduce."
- **Restated:**
  - Every pipeline phase is measured: queue wait, provisioning, checkout, restore, build, test, save, report.
  - Each phase is minimized without ever reducing verification (no false green).
  - The targets are the Q7 numbers, relative to the measured baselines: hosted 71 s, old self-hosted 174 s.
- **Passes when:**
  - Every run summary shows per-phase timings.
  - A baseline-vs-after table links run URLs on both sides.
  - The Q7 targets hold for 5 consecutive runs.

### R8 — Smart caching, auto-regeneration, scaling under load and queueing (2026-10-06)

- **Raw request:** "Cache management, auto-regeneration, scaling when many jobs arrive, queue ordering: everything must be well thought out and smart."
- **Restated:**
  - **Cache:**
    - Content-addressed keys (lockfile hash, toolchain, OS).
    - Pull requests are read-only; the default branch writes.
    - Integrity digests are verified.
    - A size budget with LRU/TTL eviction.
    - A hit-ratio metric.
    - Never reuse stale binaries: the design must eliminate the `scripts/ci/cache-restore.sh:123-128` HYPOTHESIS.
  - **Scaling:**
    - The controller scales runners per pool with queue depth, within host CPU / RAM / disk ceilings.
    - Min/max warm pool, and scale-to-zero when idle.
    - Overflow to hosted runners when the pool is saturated or unavailable (Q2).
  - **Queueing:**
    - Cancel superseded runs on the same ref (concurrency groups).
    - Priority classes: default branch > pull request > schedule.
    - Shortest job first within a class, from historical durations.
    - A job waiting past a deadline overflows to hosted.
  - **Regeneration:** see R5.5.
- **Passes when:**
  - A load test with N simultaneous jobs shows the pool reach its ceiling and return to zero within the agreed times.
  - Controller logs show the priority order.
  - Superseded runs are cancelled.
  - The summary shows the cache hit ratio.
  - A mutation test proves the tests fail when the queue logic is wrong.

### R9 — Clean architecture and large-scale engineering practice (2026-10-06)

- **Raw request:** "Coding style is clean architecture plus big-tech enterprise best practice."
- **Restated:**
  - The controller and tooling are layered as domain / application / infrastructure, with dependencies pointing inward.
  - Providers (Proxmox, VPS, …) are adapters behind ports.
  - Typed code, with unit tests for the domain.
  - Lint, format and static analysis run in CI.
  - Architecture decisions are recorded as ADRs.
  - Conventional commits, and PRs of 30 files or fewer.
- **Passes when:**
  - A test or linter enforces the dependency rule and fails when the domain imports infrastructure.
  - Domain coverage meets the threshold set in design.
  - CI gates are green.
  - Every architecture decision has an ADR.

### R10 — Portable to VPS, on-prem and other hosts (2026-10-06)

- **Raw request:** "When this project is done, it becomes a base I can apply to VPS, on-prem and other machines."
- **Restated:**
  - Hypervisor-specific code sits behind an adapter boundary.
  - Everything else is provider-neutral: Ansible roles for runner / cache / controller, the controller core, the workflows.
  - At least one non-Proxmox target is documented and proven.
- **Passes when:**
  - A porting guide exists.
  - A run proves the same roles converge on a GitHub-hosted Ubuntu VM, and a runner registered from there runs a job green.
  - WSL Debian does not count as evidence: it shares the Windows kernel and has no systemd by default, so it is a poor VPS stand-in.

### R11 — An AI coding agent is the operator; the previous agent is retired (2026-10-06)

- **Raw request:** "This work no longer uses [the previous agent]. You are now the one in charge of doing the work; [the previous agent] has stepped away."
- **Restated:**
  - Every change goes through an operator-authored PR, and the owner merges; the operator never merges.
  - No more direct pushes to master.
  - Repo docs that address the previous agent (`AGENTS.md`, `HANDOFF.md`) are updated.
  - Addendum (2026-10-06, owner, second session): "[This project is no longer set up for the previous agent's vendor; rename that vendor-specific wording to 'agent'; development continues with the current operator only, implemented on this machine.]" The vendor-specific agent guide (removed in #56): its still-generic rules move into the vendor-neutral `AGENTS.md`. A vendor-named pointer file is not added unless the owner asks. Update (2026-10-06, owner): add a one-line pointer file that imports `AGENTS.md`, named for the operator's tooling, so that tooling loads the same guide.
- **Passes when:**
  - Every master commit in the last 30 days came through a PR (criterion 4.5(a)).
  - A case-insensitive grep of the repo for the previous agent's name leaves no instruction aimed at it.

### R12 — Requirements complete before implementation (2026-10-06)

- **Raw request:** "Before implementing, write a complete, detailed requirements document with no unclear point, and only then start implementing."
- **Restated:** this document reaches `AGREED` (all blocking questions closed, 7.2 filled) before any round-4 implementation PR.
- **Passes when:** the header status is `AGREED` and every blocking row has a closing date. Met on 2026-10-06.

### R13 — PVE 9 and entirely new credentials (2026-10-06)

- **Raw request:** answer "1" to the high-risk question: do the PVE 9 move and rotate credentials once a restore point exists.
- **Restated:**
  - A fresh PVE 9 install on the new machine, so there is no upgrade step.
  - Every credential is new: root password, API tokens, cache keys, GitHub tokens.
  - No value from the old host or the repo history is reused.
  - Credentials are stored per Q6 and never printed.
  - Before every risky step, a restore point exists:
    - a Hyper-V checkpoint taken only while the VM is stopped, or a copy of the VHDX;
    - a checkpoint of a running VM with `ExposeVirtualizationExtensions` is unproven (operator notes, outside the repo);
    - which method works stays a `HYPOTHESIS` until Phase 1 tries it.
  - Purging git history remains the owner's task.
- **Passes when:**
  - `gitleaks` finds 0 on the new tree.
  - A by-value check against the five old values finds 0 matches.
  - Secret store listings show names only.

### R14 — The 100-point standard is the scoring frame (2026-10-05, carried over)

- **Raw request:** earlier brief: the 100-point standard ([`standard/README.md`](../../standard/README.md), #55) — the goal: 25 criteria.
- **Restated:**
  - Every phase names the criteria it touches.
  - Only evidence stored through the scorecard (#55) counts.
  - The blocking condition "Proxmox VE 8.4" clears once PVE 9 is live.
  - The blocking condition "untrusted execution" clears once every runner is ephemeral.
- **Passes when:** the scorecard shows gains, each with evidence pointing at real runs or commits.

### R15 — Runners cannot reach any private network the host is attached to (2026-10-06, derived from measurement)

- **Raw request:** none directly. Measurement shows the host routes 7 private prefixes over a VPN interface (section 3, row 22), plus tailnet peers and the home LAN.
- **Restated:**
  - Code running in a runner (from a public repo) cannot reach:
    - the VPN-routed prefixes
    - tailnet peers
    - the home LAN
    - the Windows host
    - the PVE management interface (`:8006`, `:22`)
  - Two layers enforce this: the PVE firewall, and a Windows firewall bound to the VM's NAT.
  - Allowed egress follows criterion 1.5.
- **Passes when:** every negative test below, run from inside each runner class, fails, both before and after host and VM reboots. The results are stored as evidence for criteria 1.3 and 1.5.
  - `nc -z -w2 <a VPN-routed address> 53`
  - `nc -z -w2 <tailnet peer> 22`
  - `nc -z -w2 <LAN gateway> 80`
  - `nc -z -w2 <windows host> 445`
  - `nc -z -w2 <pve mgmt> 8006`

### R16 — A neutral, English-only baseline (2026-10-06)

- **Raw request:** "I intend this project to be a homelab that can be taken in any direction. Design it neutrally; do not reference or mention any employer or organization. Make it a good baseline; I will adapt it myself later. And make it full English."
- **Restated:**
  - The repo, its docs, PR bodies and this document name no employer, organization or team.
  - Attribution is "owner" or "maintainers".
  - Identity rules are generic: never commit with a work identity.
  - Every artifact is in English.
- **Passes when:**
  - A deny-list grep returns 0 lines over the repo, the open PR branches and the PR bodies. The patterns are kept outside the repo, in the operator's notes.
  - Known hits on 2026-10-06:
    - `AI_CONTEXT.md:16`
    - the vendor-specific agent guide, lines 45-62
    - `wiki/08-Runtime-Support-and-Upgrade-Plan.md:3` (team name)
    - in #55: `standard/README.md` and 4 evidence records (team name)
  - No non-English text remains in repo docs.

### R17 — Every finalized decision is recorded as an ADR (2026-10-06)

- **Raw request:** "record the decisions as ADRs for each part: why this approach, why this tool" (owner, 2026-10-06, after Phase 1).
- **Restated:**
  - Each finalized decision (approach or tool) gets one ADR under `docs/adr/NNNN-<slug>.md` with context, the options considered, the decision and the trade-offs, citing repository lines, pull requests or measured values.
  - The pull request that finalizes a decision carries its ADR; superseding means a new ADR and a "Superseded by" line on the old one.
  - Open decisions get no ADR until decided.
- **Passes when:** every `DECIDED` row in section 6 maps to an ADR in the index `docs/adr/README.md`. On 2026-10-06, D1–D45 except the open D10/D11 map to ADRs 0001–0018 (PR #60).

---

## 2. Scope / Non-scope

> In scope: the whole platform on this machine, from Hyper-V to runbook. Out of scope: organization-specific baselines, Kubernetes, the old host, and GitHub settings other than secrets.

### 2.1 In scope

| # | What | Files / systems |
|---|---|---|
| 1 | Enable Hyper-V (elevated script, owner accepts UAC); post-reboot regression gate | Windows features on this machine |
| 2 | Create the VM by script; install PVE 9 unattended with an answer file | Hyper-V, ISO, `scripts/hyperv/`, `iac/bootstrap/` |
| 3 | Network: Internal switch + WinNAT + static IP; remote access by SSH key over the tailnet. Refined 2026-10-06 (D20): PVE itself stays off the tailnet; SSH jumps through the Windows host, which is the tailnet node | Hyper-V vSwitch, WinNAT, PVE network |
| 4 | IaC foundation: provider adapters, inventory of N hosts, secret store, state backend with locking, IaC CI | `iac/`, `.github/workflows/` |
| 5 | Templates from the flavor catalog, with a scheduled rebuild pipeline and versioning | `iac/`, `templates/` (new) |
| 6 | Cache service with policy, eviction, integrity and metrics; no stale binaries | cache CT, `scripts/ci/`, workflows |
| 7 | Runner pool controller: JIT ephemeral runners, scaling, queueing, overflow to hosted | `controller/` (new), PVE API, GitHub API |
| 8 | Reusable per-node workflows, per-phase timing, optimization | `.github/workflows/`, `.github/actions/` |
| 9 | Observability, backups with timed restore, drills | monitoring CT, backup storage |
| 10 | Runbook, knowledge, porting guide, portability proof | `docs/` or `wiki/`, memory |
| 11 | Cutover: deregister old runners and retire the old host. Deregistering changes GitHub, so it runs only on the owner's explicit go | GitHub runners API |
| 12 | Set new CI secrets through `gh` (approved by the owner in R13) | GitHub Actions secrets, `cache-writer` Environment |
| 13 | Neutrality and English pass over the repo and the open PRs (R16) | repo docs, PR #52, PR #55 |

### 2.2 Out of scope

| Not doing | Because | If wanted |
|---|---|---|
| Organization-specific runner classes, labels or baselines | The owner adapts the neutral baseline later (R16) | The owner forks and opens a new kickoff |
| Terragrunt, mise or other organization-specific IaC conventions | The owner chose OpenTofu + Ansible best practice first (D2) | Add with a decision-log reason |
| Kubernetes or a Kubernetes-based runner controller | Too heavy for the laptop budget; one more layer to operate | New decision if a bigger host appears |
| Fixing the old host (disk, offline runners, applying #40 there) | The owner retired it | — |
| Purging git history; other GitHub settings (visibility, branch protection, fork approval, SHA pinning) | Owner-only | The owner acts; the operator prepares exact commands |
| Merging PRs | The operator never merges; the owner does | The owner merges |
| Changing the sample apps (`apps/`) beyond what workflows need | Not a platform goal | Separate task |
| Performance claims without measurement | Evidence-first | Measure first |

---

## 3. Measured constraints

> Hardest constraints:
> - a laptop used daily for other work
> - a Wi-Fi-only uplink
> - one 477 GiB disk with 160.9 GiB free, about 20.9 GiB after the 140 GiB VM cap
> - unproven nested KVM

| # | Fact | Label | Evidence |
|---|---|---|---|
| 1 | Windows 11 Pro build 26200 on the workstation | `CONFIRMED` | `Get-CimInstance Win32_OperatingSystem` 2026-10-06 |
| 2 | AMD Ryzen 7 PRO 5850U, 8 cores / 16 threads, `VirtualizationFirmwareEnabled=True` | `CONFIRMED` | `Win32_Processor` 2026-10-06 |
| 3 | 43.8 GiB RAM, 24.0 GiB free at measurement | `CONFIRMED` | `Win32_ComputerSystem`, `Win32_OperatingSystem` 2026-10-06 |
| 4 | One NVMe disk, 477 GiB; C: 160.9 GiB free of 475.9 GiB (20.7 GiB on 2026-09-30) | `CONFIRMED` | `Get-Volume`, `Get-PhysicalDisk` 2026-10-06; operator notes (outside the repo) |
| 5 | Largest consumers: the container-engine disk image 24.9 GiB and user data | `CONFIRMED` | scan 2026-10-06 |
| 6 | Hyper-V role not installed (`Microsoft-Hyper-V-All : Disabled`); VirtualMachinePlatform and WSL enabled; a hypervisor already runs | `CONFIRMED` | `Win32_OptionalFeature`, `HypervisorPresent=True` 2026-10-06 |
| 7 | VBS running (`VirtualizationBasedSecurityStatus=2`), HVCI on | `CONFIRMED` | `Win32_DeviceGuard` 2026-10-06 |
| 8 | This shell is not elevated; the account is a local administrator, so admin steps need the owner's UAC approval | `CONFIRMED` | `IsInRole(Administrator)=False`, `Get-LocalGroupMember` 2026-10-06 |
| 9 | Wi-Fi is the only uplink. Other adapters: a host VPN adapter, a mesh VPN (tailnet) adapter, WSL. No NAT object exists | `CONFIRMED` | `Get-NetAdapter`, `Get-NetNat` 2026-10-06 |
| 10 | No sleep on AC power (`STANDBYIDLE` AC = 0) | `CONFIRMED` | `powercfg /query` 2026-10-06 |
| 11 | The PVE 9.2 ISO does not boot on Hyper-V Gen2; 9.1-1 does (Bugzilla 8027) | `HYPOTHESIS` | forum.proxmox.com thread 183899 (2026-07-05); re-check bug 8027 before downloading |
| 12 | No report confirms nested KVM on mobile Zen 3 inside a Hyper-V Linux guest | `HYPOTHESIS` | operator notes (outside the repo); only a smoke test settles it |
| 13 | Proxmox does not support Docker in LXC: "We do not support Docker containers on top of LXC containers" | `CONFIRMED` | forum.proxmox.com/threads/docker-integration.175870 (quoted in the operator notes, outside the repo) |
| 14 | Hyper-V nested virtualization needs static memory, so the VM's RAM is reserved while it runs | `RULED OUT` as worded (2026-10-06): Microsoft states no static-memory requirement; its text covers Hyper-V running inside the VM, not KVM. The VM still uses static memory by choice (D19, D35), so its RAM is reserved while it runs | "When Hyper-V is running inside a virtual machine, the virtual machine must be turned off to adjust its memory. Meaning that even if dynamic memory is enabled, the amount of memory doesn't fluctuate. Simply enabling nested virtualization has no effect on dynamic memory or runtime memory resize." (learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/nested-virtualization, read 2026-10-06) |
| 15 | Baseline: hosted full suite, cold cache, 71 s.<br>Per job: Telemetry 5 s, Build 19 s, Test .NET 29 s, Angular 35 s, Report 3 s; queue ≤ 5 s | `CONFIRMED` | run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969), job-level data |
| 16 | Baseline: old self-hosted, 174 s. Report queued 64 s, because the `dotnet` label had one runner | `CONFIRMED` | run [37341728563](https://github.com/ugritchaichana/booth-homelab/actions/runs/37341728563) attempt 2, job-level data |
| 17 | The current build cache saves about 1 s (4630 → 3616 ms) | `CONFIRMED` | job 111502928303 vs 111503888437 |
| 18 | The restore bumps only files changed since `HEAD~1`, on top of `latest.tar.zst`, which records no SHA. A multi-commit push may therefore reuse stale binaries | `HYPOTHESIS` | `scripts/ci/cache-restore.sh:123-128` |
| 19 | The repo is public and owned by a personal account, which registers runners per repo only (no organization) | `CONFIRMED` | `gh api repos/ugritchaichana/booth-homelab` → `visibility: public`, owner type User |
| 20 | `GITHUB_TOKEN` cannot list runners or mint JIT configs; a token with Administration permission is needed | `CONFIRMED` | operator notes (outside the repo); `scripts/proxmox/ephemeral/homelab-ephemeral-runner.sh:47,79` |
| 21 | The personal token lacks `read:project`, so GitHub Project #4 is unreadable | `CONFIRMED` | `gh project view 4` → "missing required scopes [read:project]" |
| 22 | A host VPN interface routes 7 private prefixes through this host. A VM behind the host's NAT could reach them unless blocked | `CONFIRMED` (routes) / `HYPOTHESIS` (VM reachability) | `Get-NetRoute` on the VPN interface 2026-10-06 |
| 23 | A mesh VPN (tailnet) adds a /32 route per peer (e.g. the retired `pve` host). The home LAN is reached over Wi-Fi | `CONFIRMED` | the mesh VPN's status command, `Get-NetRoute` 2026-10-06 |
| 24 | The repo's tests use no Docker: no Testcontainers and no Docker client. Test packages are only `Microsoft.NET.Test.Sdk`, `coverlet.collector`, `xunit` and `xunit.runner.visualstudio` | `CONFIRMED` | `git grep -i 'Testcontainers\|DockerClient\|docker run'` over `apps`, `scripts/apps`, `tests` = 0 lines; `PackageReference` in `apps/backend/tests/*.csproj` |
| 25 | Two repos in the account have workflows: `booth-homelab` (8) and one other repository in the account (1). All repos are public | `CONFIRMED` | `gh api users/ugritchaichana/repos` + `contents/.github/workflows` 2026-10-06 |
| 26 | Standard GitHub-hosted runners are free for public repos: "GitHub Actions usage is **free** for **self-hosted runners** and for **public repositories** that use standard GitHub-hosted runners." | `CONFIRMED` | docs.github.com/en/billing/concepts/product-billing/github-actions (read 2026-10-06) |
| 27 | Routing picks hosted only for `force_ubuntu_runner` or `github.repository != 'ugritchaichana/booth-homelab'`. Fork PR events run in the base repo, so fork PRs land on self-hosted runners. The old `pve-runner-01` was still online | `CONFIRMED` | `.github/workflows/reusable-sdet-pipeline.yml:60-63`; "For pull requests from a forked repository to the base repository, GitHub sends the `pull_request` … events to the base repository." (docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows, read 2026-10-06); `gh api …/actions/runners` 2026-10-06 00:43 ICT |
| 28 | RAM available 24.5 GiB of 43.8 GiB, committed 29.8 GB, with WSL `docker-desktop` and `Debian` both stopped; no `.wslconfig` memory cap. A 24 GiB static VM would leave about 0.5 GiB | `CONFIRMED` | `\Memory\Available MBytes` = 25076, `wsl -l -v`, 2026-10-06 (Phase 1 discussion) |
| 29 | C: 159.7 GiB free; a VHDX grown to 140 GiB would leave 19.7 GiB, below the Q1 floor | `CONFIRMED` | `Get-Volume C` 2026-10-06 (Phase 1 discussion) |
| 30 | Proxmox Bugzilla 8027 "Cannot be installed in nested Hyper-V": status NEW, last change 2026-09-10, no fix | `CONFIRMED` | bugzilla.proxmox.com/show_bug.cgi?id=8027, read 2026-10-06 |
| 31 | `10.99.0.0/16` overlaps no route or address on the host (the occupied private ranges are the VPN prefixes of row 22, the WSL `/20`, the home LAN and tailnet `/32`s); no NAT object exists | `CONFIRMED` | `Get-NetRoute`, `Get-NetIPAddress`, `Get-NetNat` 2026-10-06 |
| 32 | The laptop is the owner's personal machine (owner, G1; refined 2026-10-06 by D42: used by the owner alone, every local administrator inside the trust boundary). Not joined to Azure AD, a domain or a workplace; no external MDM enrollment (only Windows' built-in provisioning authorities); no DeviceGuard or Hyper-V policy | `CONFIRMED` | `dsregcmd /status`, `HKLM:\SOFTWARE\Microsoft\Enrollments`, `PolicyManager\current\device` 2026-10-06 |
| 33 | Elevation works: a no-op `Start-Process -Verb RunAs` returned `elevated=True`, High integrity, exit 0 in 3 s after the owner accepted UAC. Hyper-V Administrators has 0 members; UAC `ConsentPromptBehaviorAdmin=5`; Memory Integrity running and not UEFI-locked; Windows `sshd` installed but Stopped/Manual, nothing listens on :22 | `CONFIRMED` | UAC test and `Get-LocalGroupMember`, `Win32_DeviceGuard`, `Get-Service sshd` 2026-10-06 |
| 34 | The owner enabled Hyper-V and rebooted (boot 2026-10-06 11:41 ICT). All `Microsoft-Hyper-V*` features Enabled, `vmms` Running, `HypervisorPresent=True`; default VM configuration version 12.0 (AMD nested needs ≥ 9.3); no VM, no NAT; switches: Default Switch (an internal prefix) and the WSL switch. Regression gate green: WSL Debian booted in 3 s, Docker Desktop engine up in 34 s and `hello-world` ran, C: 181.2 GiB free, the host VPN up with its 7 prefixes, tailnet backend Running (self online). `10.99.0.0/16` still free. Hyper-V Administrators still has 0 members, so `Get-VM` needs elevation | `CONFIRMED` | `Win32_OptionalFeature`, `Get-Service vmms`, elevated `Get-VMHost` / `Get-VMHostSupportedVersion` / `Get-VMSwitch`, `wsl -d Debian -- uname -r`, `docker run --rm hello-world`, `Get-Volume C`, `Get-NetRoute`, the mesh VPN's status command 2026-10-06 |
| 35 | Phase 1 elevated run 2 (2026-10-06 15:53–16:02 ICT, exit 0): 18 port ACLs read back and the adapter connected; the unattended 9.1-1 install finished in 459 s and powered the VM off (`reboot-mode = "power-off"` works on 9.1-1); ISO ejected with read-back; checkpoint `post-install` taken while Off without the ISO; first cold start: TCP 22 answered 18.1 s after `Start-VM`; ISO copy deleted | `CONFIRMED` | transcript `New-PveHost-20261006-155339.log` in `%LOCALAPPDATA%\homelab\logs` |
| 36 | `pve-manager/9.1.1/42db4a6cf33dac83 (running kernel: 6.17.2-1-pve)`; `systemd-detect-virt` = microsoft; `egrep -c "vmx\|svm"` = 12; `/dev/kvm` present; `kvm_amd nested` = 1. Nested KVM works with Memory Integrity on, so D27's test is not needed and D9's VM class is available | `CONFIRMED` | SSH from Windows, 2026-10-06 16:03 ICT |
| 37 | Hyper-V extended port ACLs on this host: a stateful rule is accepted only for TCP or UDP (ICMP, `ANY` and no protocol are rejected with 0x80070057 when the adapter connects); a stateful Deny is rejected; weight 65535 is accepted, 100000 rejected. Run 1 (15:04) failed closed on this before the VM ever started | `CONFIRMED` | probe on a throwaway, never-started VM, `acl-probe-20261006-152843.log` (the install replay reproduced the error exactly) |
| 38 | R15 host-side layer measured from PVE (no runner exists): guest to the host (445/135/139), the home router (80/53), the host's Wi-Fi address, its tailnet and mesh-VPN addresses and the mesh DNS server are all dropped (timeout), each paired with Windows reaching the same target; HTTPS and DNS via 1.1.1.1 work; ICMP to the internet fails by design (stateful TCP/UDP only); IPv6 has no route. Not measured: the two harvested host-routed prefixes (no host in them was reachable even from Windows at the time), UDP to the host, and each plane alone (needs Hyper-V rights) | `CONFIRMED` / `NOT MEASURED` as stated | operator notes (outside the repo; addresses as labels) |
| 39 | WSL (NAT mode) cannot reach `10.99.0.2` directly (TCP 22 timeout); SSH through `ProxyCommand` with the Windows `ssh.exe -W %h:%p` works | `CONFIRMED` | operator notes (outside the repo), checks W1–W3 |
| 40 | Regression gate with the VM running: WSL Debian boots in 2.3 s; Docker Desktop starts and `hello-world` exits 0; available RAM never below 6049 MB (7051 MB at the end); C: 163.9 GB free; 7 VPN prefixes; both mesh-VPN services Running; host internet OK | `CONFIRMED` | operator notes (outside the repo) |
| 41 | D40 role `pve_repos` (PR #59) applied from WSL through the `ProxyCommand` hop: enterprise and ceph repositories `Enabled: no`, `pve-no-subscription` `Enabled: yes`; pve-manager 9.1.1 → 9.2.21, kernel 6.17.2-1-pve → 7.0.14-20-pve; 0 pending upgrades; second run `changed=0`; nested KVM still PASS on 7.0.14 (svm 12, `/dev/kvm`, nested 1). The first attempt's Ansible process never received the long upgrade's result through the proxy hop (the 214-package upgrade finished on the host); async/poll and keep-alives were added but not yet exercised on a long upgrade | `CONFIRMED` / open item as stated | operator notes (outside the repo), lead re-run 2026-10-06 ~17:30 ICT |
| 42 | R15 after the reboot (Hyper-V Administrators active, VM started non-elevated): ACL read-back 18 rules, 0 outside 4000–4999, `::/0` and `ANY` read back, one entry per stateful rule, spoofing Off, guards On, IPv6 binding reads False; host→guest and guest egress rows PASS with paired controls; MAC spoofing (scripted, no console) drops traffic and the restored MAC passes; ACLs removed for 14.8 s and restored to 18; folder ACL 4 ACEs, no inheritance, VHDX carries the per-VM ACE. With the Windows Firewall rule disabled for 10.6 s, the port ACLs alone still block guest→host 445 and the stateful mirror (source port 8006) toward the host, while 1.1.1.1:443 opens. Harvested-prefix row NOT MEASURED (no address inside those prefixes answers even from Windows); guest ICMP to the Internet is dropped by the ACL plane (no stateful ICMP on this switch) | `CONFIRMED` | operator notes (outside the repo) |
| 43 | D40 role proven from the fresh install (`post-install` restored): run 1 `ok=8 changed=5 unreachable=0 failed=0` in 254 s including the reboot into 7.0.14-20-pve, the upgrade result returned through the `ProxyCommand` hop; run 2 `changed=0`. A first attempt was invalid: the laptop entered Modern Standby 1 minute in (on battery), suspended the VM and the control process was stopped on resume | `CONFIRMED` | operator notes (outside the repo), two runs; Kernel-Power events 506/507 |
| 44 | PVE 9.2.21 host facts: `sudo` absent; sshd `permitrootlogin yes`, `passwordauthentication yes`; pveproxy `*:8006` and spiceproxy `*:3128` on all interfaces, pvedaemon loopback; PVE firewall disabled; `hv_sock` loaded; dnsmasq absent; `local` storage allows `import`; Debian 13 LXC template listed; `/cluster/sdn/zones` POST needs `SDN.Allocate` on `/sdn/zones`, node firewall rules need `Sys.Modify` on `/nodes/{node}` | `CONFIRMED` | operator notes (outside the repo) |
| 45 | Stopped-VM checkpoint action live: refusal while Running (exit 1); first success run created the checkpoint but the immediate `Get-VMSnapshot` read listed it 0 times (stale read, false FAIL); with `-Passthru` + polling by Id: PASS in 6.5 s; duplicate name refused; cold starts after restore 16 s, 16 s, 15.8 s, 15.7 s; disk chain 17.7 GiB with 3 checkpoints | `CONFIRMED` | PR #61 body |
| 46 | Ansible converge on pve01 (PVE 9.2.21) as `automation` after a root bootstrap (`ok=11 changed=4`). Run 1 failed closed on a missing secret directory (the rescue removed the new token); run 2 failed on a false-positive firewall compile check, and the firewall dead-man fired on the real host and restored the previous state (`restore finished rc=0`). After the fixes: run 3 `ok=129 changed=14 failed=0`, run 4 `ok=113 changed=0`; runs 6–7 on the final state (guest network and probe guests present) and run 8 after the probe teardown `ok=114 changed=0 unreachable=0 failed=0` | `CONFIRMED` | PR #65, #66, #67 bodies |
| 47 | Host baseline after converge and after the PVE and laptop reboots: sshd `permitrootlogin without-password`, password and keyboard-interactive off; password login and the control node's key as root → `Permission denied (publickey)`; the Windows break-glass key as root from 10.99.0.1 works; `hv_sock` loaded 0 with `install /bin/false`; IPv6 accept_ra, autoconf and `all.forwarding` 0; pve-firewall enabled/running; the guest-firewall guard timer active, seen stopping a half-created VM (`VIOLATION vmid=9102 … firewall not enabled`) | `CONFIRMED` | PR #67 body |
| 48 | OpenTofu token `tofu@pve!provisioner`: `/version` 200, create user 403; effective privileges `/` none, `/sdn/zones/localnetwork` none, `/sdn/zones/hlab/guests` SDN.Allocate/Audit/Use, `/pool/homelab` VM.Allocate/Audit/Config.{CPU,Cloudinit,Disk,HWType,Memory,Network,Options}/PowerMgmt. Two 403s seen only on the host: tags at create (PVE checks tag permission without the pool, so a pool-scoped token cannot tag at create; tags dropped) and `Datastore.Audit` on the disk storage (granted). Deleting a volume needs `Datastore.Allocate` on the storage, which would also delete any volume there and read the storage config: not granted, so the probe teardown needs one operator `pvesm free` per downloaded file | `CONFIRMED` | PR #67, #71 bodies |
| 49 | OpenTofu host stack: apply "5 added"; `plan -detailed-exitcode` rc 0 after the apply, after the state-copy fix and after the probe teardown; state mode 600 with `encrypted_data` and 0 plaintext `resources`; a concurrent plan → `Error acquiring the state lock`; a wrong passphrase → `decryption failed … message authentication failed`; an encrypted copy written on the Windows side; Ansible state survived a VM restart (firewall on, guard active, `ifquery --check -a` rc 0). Lock and passphrase reds re-run after the laptop reboot with the same result | `CONFIRMED` | PR #68 body; operator notes (outside the repo) |
| 50 | Guest network: SDN zone `hlab`, vnet `guests` 10.99.16.1/24 with port isolation; SNAT is `-j SNAT --to-source 10.99.0.2` (not MASQUERADE); forwarding is per interface (guests and vmbr0 1) while `all.forwarding` stays 0 | `CONFIRMED` | PR #70 body |
| 51 | R15 red-first (pve-firewall stopped), both guests: gateway and management SSH and web console OPEN, so the PVE layer is what blocks those rows; every external row still dropped by the Windows layer; guest to guest direct unreachable and via the gateway dropped (port isolation holds without the firewall) | `CONFIRMED` | PR #71 body |
| 52 | R15 with the firewall on, per guest (container and VM), 15 negatives and 1 egress positive with paired controls: baseline, after a container reboot, after a PVE reboot and after a laptop reboot each `negatives_blocked=15/15 positives_ok=1/1 egress_curl=200`. Two rows NOT MEASURED in every phase (VPN peer web, harvested-prefix host): no Windows-side positive exists, so a block cannot be told from an absent service | `CONFIRMED` | PR #71 body |
| 53 | After the laptop reboot: VM started non-elevated, SSH 15.8 s after start; ACL read-back 18 (4 stateful rules = 4 entries, `::/0` twice, protocol `ANY`), host rule Block, IPv6 binding False; web UI through the tailnet and through the port proxy 200. Regression gate: WSL 1.8 s, Docker `hello-world` rc 0, 12449 MB RAM free with the VM and Docker running, C: 146.4 GB free | `CONFIRMED` | operator notes (outside the repo) |
| 54 | IaC CI (both jobs: Ansible lint, syntax and Molecule; OpenTofu lint, validate and test) green at the current head of every chain PR: #62 37476645272, #63 37476650705, #64 37507733294, #65 37520875620, #66 37520886757, #67 37552511684, #68 37552514424, #69 37552517008, #70 37552520151 (10 passed), #71 37552523015 (10 + 10 passed, probe harness), #72 37552526486, #73 37552529539, #74 37552532600. The repository-wide .NET build is red on #57, #58 and master `179f826` alike (inherited, not Phase 2) | `CONFIRMED` | run IDs |

---

## 4. Assumptions and open questions

> All 8 blocking questions closed on 2026-10-06. The 7 non-blocking ones proceed on the stated assumptions.

| # | Question / assumption | Blocking? | Who | Status |
|---|---|---|---|---|
| Q1 | Resource budget for the PVE VM | `blocking` | owner | closed (2026-10-06):<br>• 12 vCPU / 24 GiB static RAM / 140 GiB max VHDX<br>• C: keeps ≥ 20 GiB free (160.9 − 140)<br>• revised 2026-10-06 by D19 (rows 28–29): 12 vCPU / 20 GiB static / 128 GiB |
| Q2 | Behaviour when the laptop is off or asleep, the VM is stopped, or the pool is full | `blocking` | owner | closed (2026-10-06):<br>• overflow to hosted automatically<br>• the owner creates a fine-grained token (Administration read) for the router job |
| Q3 | Repos served (finding: 2 repos have workflows; personal accounts register runners per repo) | `blocking` | owner | closed (2026-10-06):<br>• `booth-homelab` only<br>• the repo list is configuration |
| Q4 | Meaning of "several machines" | `blocking` | owner | closed (2026-10-06): independent hosts in one inventory (PVE, VPS or plain Linux), not a Proxmox cluster |
| Q5 | A Docker-capable runner class now? (finding: current tests use no Docker; container-based integration tests are a common baseline need) | `blocking` | owner | closed (2026-10-06): yes.<br>• a VM if nested KVM works; otherwise Docker jobs go to hosted<br>• never privileged LXC for public-repo code<br>• proven by a job running `docker run hello-world` |
| Q6 | Where secrets live | `blocking` | owner | closed (2026-10-06):<br>• SOPS + age in the repo for IaC secrets<br>• the age key in the Windows profile, with an owner-held backup<br>• CI secrets set through `gh`, showing names only |
| Q7 | Laptop's role versus hosted, and speed targets | `blocking` | owner | closed (2026-10-06): the laptop is the primary path and must beat hosted. Targets, each held for 5 consecutive runs:<br>• full suite ≤ 60 s with warm caches<br>• queue-to-start p95 ≤ 10 s<br>• scale-from-zero to job start ≤ 30 s<br>• cache hit ≥ 95% on an unchanged lockfile |
| Q8 | Build the controller or adopt one (e.g. GARM) | `non-blocking` | operator (design) | open — criterion: supports Proxmox without Kubernetes, and forkable |
| Q9 | Controller language | `non-blocking` | operator (design) | open — typed, simple to deploy, able to enforce clean architecture |
| Q10 | Who holds the PVE root password | `non-blocking` | per Q6 | assumption: random, stored per Q6; automation uses SSH keys and API tokens only |
| Q11 | When to enable Hyper-V and reboot | `non-blocking` | owner | assumption: the owner picks the time in Phase 1; the operator prepares the script |
| Q12 | Merge process | `non-blocking` | — | assumption: the operator opens PRs; the owner merges |
| Q13 | Language of repo docs | `non-blocking` | — | closed (2026-10-06) by R16: English everywhere |
| Q14 | Observability stack | `non-blocking` | operator (design) | assumption: lightweight, since RAM is reserved statically (row 14) |
| Q15 | Public-repo CI on a host attached to private networks (row 22) | `blocking` | owner | closed (2026-10-06):<br>• isolate per R15<br>• fork PRs always run on hosted<br>• self-hosted runs only the repo's own refs |

`blocking` means a wrong guess forces rework of the whole effort. Status cannot move to `IN-PROGRESS` while any `blocking` row is `OPEN`.

---

## 5. Plan

> Nine phases.
> - Phase 0 is this document.
> - Phases 1–2 touch only this machine.
> - The repo's CI is first affected in Phase 6 (cutover), which records its own blast radius before starting.

### Phase 0 — Requirements AGREED

- **Do:** close Q1–Q7 and Q15; fill 7.2.
- **DONE WHEN:** status is `AGREED`. Met on 2026-10-06.
- **Proof:** this header and the closing dates in section 4.

### Phase 1 — Machine and hypervisor

- **Do:**
  - Before the reboot, write a resume prompt in the operator notes. It is the prompt the owner pastes to start a new session, because the Hyper-V reboot ends the operator's session. It carries:
    - the state and the next steps;
    - the post-reboot regression gate: `wsl -l -v`, start Docker Desktop, `Get-Volume C`, VPN and tailnet up.
  - Enable Hyper-V through an elevated script, then pass the regression gate.
  - Create the VM by script:
    - Gen2, Secure Boot off, `ExposeVirtualizationExtensions`;
    - static RAM per Q1;
    - a dynamic VHDX capped at 140 GiB;
    - an Internal switch with WinNAT.
  - Install PVE 9 unattended with an answer file. Use ISO 9.1-1 unless bug 8027 is fixed.
  - Smoke test: `egrep -c "vmx|svm" /proc/cpuinfo` and `/sys/module/kvm_amd/parameters/nested`.
  - Set up SSH keys and tailnet access.
  - Create a restore point per R13.
  - Detail decisions from the Phase 1 discussion (2026-10-06): D19–D23. Phase 1 is still not a go.
  - Grill of the remaining Phase 1 details (2026-10-06): rows 32–33, D24–D32. Phase 1 is still not a go.
- **DONE WHEN:**
  - `pveversion` shows 9.x.
  - The nested KVM result is recorded, pass or fail; on fail, D9 applies.
  - The regression gate is green.
- **Proof:** outputs of the verification checklist in the operator notes (outside the repo), stored as evidence.

### Phase 2 — IaC foundation and security baseline

- **Do:**
  - Clean repo layout with provider adapters, and an inventory of N hosts.
  - Secret store per Q6.
  - OpenTofu (`bpg/proxmox`) for storage, network, users, tokens and ACLs. Delivered differently: users, tokens and ACLs by Ansible (D47, D48); storage stays as the installer made it in Phase 2 (D63).
  - State backend with locking.
  - Ansible baseline: hardening, firewall including R15, time, logs.
  - IaC CI per criterion 2.5.
  - Publish this document in the repo (e.g. `docs/platform/requirements.md`); the repo copy becomes canonical.
- **DONE WHEN:**
  - Plan returns 0 after apply.
  - The second Ansible run reports `changed=0`.
  - Every R15 negative test fails.
  - CI is green.
- **Met on 2026-10-07** (independent audit: all four clauses met on the raw evidence):
  - Plan 0: `plan -detailed-exitcode` "No changes" after the apply, after the state-copy fix and after the probe teardown (row 49).
  - `changed=0`: the run after the probe teardown `ok=114 changed=0 unreachable=0 failed=0` (row 46).
  - R15: every negative blocked in all five phases on both guests; two extra rows NOT MEASURED as a named limitation (rows 51, 52).
  - CI: IaC CI green at the head of every chain PR #62–#74 (row 54; #60 and #61 touch no IaC path).
- **Proof:** run URLs, `tofu plan -detailed-exitcode`, negative-test output.

### Phase 3 — Templates and regeneration

- **Do:**
  - Flavor catalog with tests.
  - Golden-template build pipeline: LXC, plus VM per the Phase 1 result.
  - Versioning and rollback.
  - Scheduled rebuild.
- **DONE WHEN:** two versioned templates with manifests exist, and rollback is one command.
- **Proof:** pipeline logs and `pvesh get /nodes/<node>/storage/<s>/content`.

### Phase 4 — Cache service

- **Do:**
  - Cache store: MinIO or an alternative decided in design.
  - Ref-scoped read/write policy.
  - Content-addressed keys with digests.
  - Size budget with eviction, and a hit-ratio metric.
  - A design that rules out stale binaries.
- **DONE WHEN:**
  - The hit ratio meets Q7 on an unchanged lockfile.
  - A test proves sources changed in an earlier commit are rebuilt (red first).
- **Proof:** hit and miss run URLs, plus the once-red test.

### Phase 5 — Runner pool controller

- **Do:**
  - JIT ephemeral runner per job.
  - Queue-driven scaling within host ceilings.
  - Warm pool and scale-to-zero.
  - Priorities, cancellation of superseded runs, and overflow to hosted per Q2.
  - Role-separated tokens.
- **DONE WHEN:**
  - Every runner shows `ephemeral: true`.
  - The load test meets Q7.
  - The mutation test of the queue logic fails when broken.
- **Proof:** controller logs, `gh api …/actions/runners`, run URLs.

### Phase 6 — Reusable workflows and cutover

- **Do:**
  - Reusable per-node units.
  - Per-phase timings in the summary.
  - Optimize from measurements.
  - Route fork PRs to hosted (D17).
  - Move labels to the new pools.
  - Deregister the old runners on the owner's go.
- **DONE WHEN:**
  - The full suite meets Q7 for 5 consecutive runs.
  - No old runner remains.
- **Proof:** the 5 run URLs and the baseline-vs-after table.
- **Note:** this phase touches the repo's CI, so it records its own blast radius before starting.

### Phase 7 — Observability and resilience

- **Do:**
  - Metrics for host, pool, queue and cache.
  - Alerts: runner offline over 10 minutes, disk over 85%.
  - Backups to another device, with a timed restore.
  - Drills per criterion 3.5.
- **DONE WHEN:** evidence for criteria 3.1, 3.2, 3.4 and 3.5 is stored.
- **Proof:** drill logs with timestamps.

### Phase 8 — Runbook, knowledge and portability

- **Do:**
  - Runbook that rebuilds from zero.
  - Porting guide.
  - Proof on a non-Proxmox host.
  - Memory and ADRs.
- **DONE WHEN:**
  - The timed rebuild is green.
  - The portability proof is green.
- **Proof:** criterion 3.4 evidence and the proof run URL.

---

## 6. Decision log

> 63 rows: 59 decided, 1 superseded (D13 by D19), 3 open: D10 (controller) and D11 (language) for design, D60 for the owner. D1 and D2 were reworded on 2026-10-06 to remove organization references (R16); their substance is unchanged.

| # | Decision | Options | Chosen | **Deciding criterion** | Status | ADR |
|---|---|---|---|---|---|---|
| D1 | Template basis | organization-specific runner classes / generic cloud flavors | generic cloud flavors (`flavors.json`) | owner: neutral baseline, adapted by the owner later | `DECIDED (2026-10-06)` | — |
| D2 | IaC toolset | OpenTofu + Ansible / Terragrunt + mise / other | OpenTofu + Ansible; more tools only with a reason | owner: best practice first | `DECIDED (2026-10-06)` | — |
| D3 | Scaling model | ephemeral pool + controller / fixed warm pool | ephemeral pool + controller | owner; also clears the "untrusted execution" blocking condition | `DECIDED (2026-10-06)` | — |
| D4 | Platform host | old host / this laptop / rented VPS | this laptop (PVE 9); old host retired | owner | `DECIDED (2026-10-06)` | — |
| D5 | Credentials | keep / regenerate all | regenerate all; nothing from history | owner (answer 1) + R13 | `DECIDED (2026-10-06)` | — |
| D6 | Outer hypervisor | Hyper-V / VMware / VirtualBox | Hyper-V | VBS already runs Hyper-V; "only one software component at a time can use this hardware" (learn.microsoft.com, quoted in the operator notes, outside the repo) | `DECIDED (2026-10-06)` | — |
| D7 | VM network | External switch on Wi-Fi / Internal + WinNAT + static IP / Default Switch | Internal + WinNAT + static IP | • Wi-Fi-only uplink (row 9)<br>• External on Wi-Fi with MAC spoofing unproven<br>• Default Switch range changes at boot | `DECIDED (2026-10-06)` | — |
| D8 | ISO | 9.2-1 / 9.1-1 then upgrade | 9.1-1, then `apt full-upgrade` to the latest 9.x | the 9.2 ISO fails on Hyper-V Gen2 (row 11); re-check bug 8027 first | `DECIDED (2026-10-06)` | — |
| D9 | Docker workloads | VM (needs nested KVM) / privileged LXC / hosted | VM if nested KVM works, else hosted; never privileged LXC | owner (Q5): a baseline capability without trading isolation for public-repo code | `DECIDED (2026-10-06)` | — |
| D10 | Controller | build / adopt GARM / adopt other | — | supports Proxmox without Kubernetes, and forkable | `OPEN` | ADR when decided |
| D11 | Controller language | — | — | typed, enforces clean architecture, simple to deploy | `OPEN` | ADR when decided |
| D12 | Secret store | SOPS+age + GitHub secrets / Credential Manager / password manager | SOPS + age + GitHub secrets | owner (Q6): moves to a VPS or fork with one key (R10); matches criterion 2.4(b) | `DECIDED (2026-10-06)` | — |
| D13 | Resource budget | lean / balanced / strong | strong: 12 vCPU / 24 GiB / 140 GiB | owner (Q1): speed first (R7) | `SUPERSEDED (2026-10-06) by D19` | — |
| D14 | Pool not ready | overflow to hosted / wait | overflow to hosted automatically | owner (Q2): clears criterion 3.3; the hosted path is proven (run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969)) | `DECIDED (2026-10-06)` | — |
| D15 | Repos served | `booth-homelab` / + one other repository in the account | `booth-homelab` (list in config) | owner (Q3): narrowest token | `DECIDED (2026-10-06)` | — |
| D16 | Several machines | independent hosts in an inventory / Proxmox cluster | independent hosts | owner (Q4): fits VPS and on-prem (R10); a cluster is impossible on one machine | `DECIDED (2026-10-06)` | — |
| D17 | Public-repo CI on a host attached to private networks | isolate + forks to hosted / isolate only / refuse | isolate per R15, and fork PRs always to hosted | owner (Q15): defense in depth | `DECIDED (2026-10-06)` | — |
| D18 | Laptop's role | primary path that beats hosted / baseline only | primary:<br>• ≤ 60 s<br>• p95 queue ≤ 10 s<br>• scale ≤ 30 s<br>• hit ≥ 95% | owner (Q7); hosted is free for public repos (row 26) | `DECIDED (2026-10-06)` | — |
| D19 | Resource budget (revised) | 24 GiB / 20 GiB / 16 GiB static; 140 / 128 GiB VHDX | 12 vCPU / 20 GiB static / 128 GiB max VHDX | owner, Phase 1 discussion: rows 28–29 measured the agreed 24 GiB / 140 GiB against today's load (about 0.5 GiB RAM and 19.7 GiB disk left). 20 GiB leaves about 4.5 GiB at that load, at the 7.3 signal edge; 128 GiB leaves about 28 GiB after the ISOs | `DECIDED (2026-10-06)` | Watch 7.3's RAM signal; raise only with load-test evidence (R7/R8) |
| D20 | Remote access to PVE | PVE off the tailnet, SSH jump via the Windows host / PVE joins the tailnet with a forward-drop rule | off the tailnet; `ssh -J` through the Windows host | owner, Phase 1 discussion: with no tailnet interface inside PVE a guest has no tailnet route to leak into (R15) | `DECIDED (2026-10-06)` | — |
| D21 | VM start policy | autostart with Windows / start on demand | start on demand; while stopped, jobs overflow to hosted (D14) | owner, Phase 1 discussion: RAM stays free when the pool is not needed | `DECIDED (2026-10-06)` | The router treats a stopped VM as pool-not-ready. Q7 / D18 targets are measured with the VM running |
| D22 | Hyper-V NAT subnet | any free private range | `10.99.0.0/24` (host `10.99.0.1`, PVE `10.99.0.2`); PVE-internal bridges inside `10.99.0.0/16` | operator: row 31 shows the range is free | `DECIDED (2026-10-06)` | Re-check routes before the Phase 1 script runs |
| D23 | Phase 1 mechanics | — | • one VM; the nested-KVM smoke test runs on it<br>• the age key is created in Phase 1, before the install, so the PVE root password is stored per Q6 from the first boot<br>• the auto-install ISO is prepared with `proxmox-auto-install-assistant` in WSL Debian (`HYPOTHESIS` until it runs)<br>• first restore point: a checkpoint with the VM stopped | operator; offered to the owner in the Phase 1 discussion | `DECIDED (2026-10-06)` | The owner's off-machine age-key backup moves to Phase 1 |
| D24 | Remote access in Phase 1 (refines D20) | none / Windows `sshd` + `ssh -J` / tailnet subnet route | none: the operator and the owner use this laptop only; no new listener on Windows. D20's jump host is built only when remote access is needed | owner, G2 | `DECIDED (2026-10-06)` | — |
| D25 | VM start mechanism (refines D21) | manual / scheduled / queue watcher | a manual start/stop script now; the automatic mechanism is chosen in Phase 5 with the measured cold-start time | owner, G3 | `DECIDED (2026-10-06)` | Measure VM cold start in Phase 1 |
| D26 | Rights for VM start/stop | UAC every time / owner account in Hyper-V Administrators | Hyper-V Administrators | owner, G4: accepts that any process running as the owner can control the VM and mount its VHDX without UAC | `DECIDED (2026-10-06)` | Added by the elevated Phase 1 script; effective after the next sign-in |
| D27 | Nested KVM fails | D9 directly / one Memory Integrity off test / Memory Integrity off permanently | one diagnostic test with Memory Integrity off, then back on; D9 if KVM still fails | owner, G5 | `DECIDED (2026-10-06)` | The owner picks the restart time |
| D28 | Reboots | scripts reboot / scripts never reboot | Phase 1 scripts never reboot; they stop and say a reboot is needed | owner, G5 ("restart later") | `DECIDED (2026-10-06)` | — |
| D29 | Off-machine backup of the age key and the PVE root password | password manager / offline media / both | the owner's password manager (secure note), copied by the owner before the PVE install | owner, G6 | `DECIDED (2026-10-06)` | Refines the Phase 1 owner action (D23) |
| D30 | Check of elevated scripts before UAC | owner reads the PR first / merge then run / no owner review | no owner review; the operator runs them. Compensating controls: an independent `security-engineer` review before the run; the scripts still land through a PR (R11) carrying the real run output | owner, G7 | `DECIDED (2026-10-06)` | — |
| D31 | PVE package repository | enterprise (paid subscription) / no-subscription | `pve-no-subscription`; enterprise repo disabled | owner, G8 | `DECIDED (2026-10-06)` | — |
| D32 | Reach of the owner's go | Phase 1 only / Phases 1–2 / Phases 1–5 | Phases 1–2 continuously; stop on a red DoD, an owner-only step (UAC, reboot, key backup) and to report the nested-KVM result; Phase 3 needs a new go | owner, G9 | `DECIDED (2026-10-06)` | — |
| D33 | Operator toolchain home | Windows native / WSL Debian / both | WSL Debian for `tofu`, `sops`, `age`, `ansible`, `xorriso`, `proxmox-auto-install-assistant`, installed by a pinned repo script; release binaries checked against the publisher's SHA256 list. The age key stays in the Windows profile per Q6 (`%APPDATA%\sops\age\keys.txt`); WSL reads it through `SOPS_AGE_KEY_FILE` | operator: Ansible and the assistant are Linux-only; one toolchain matches Linux CI; inventory 2026-10-06 shows none of these installed on either side | `DECIDED (2026-10-06)` | WSL → `10.99.0.2` reachability is a `HYPOTHESIS`, tested the moment PVE answers; fallback `ProxyCommand` through Windows `ssh.exe -W`, no new listener (D24) |
| D34 | PVE install filesystem | ext4 on LVM-thin / ZFS | ext4 on LVM-thin (installer default) | operator: "ZFS uses 10 % of the host memory, clamped to a maximum of 16 GiB, for ARC by default" (operator notes, outside the repo), memory the 20 GiB VM (D19) needs for guests; LVM-thin still gives snapshots and linked clones | `DECIDED (2026-10-06)` | — |
| D35 | VM mechanics | — | • static MAC; dynamic memory off; automatic checkpoints off; automatic start Nothing (D21); automatic stop ShutDown<br>• boot order disk first, DVD second, plus answer-file `reboot-mode = "power-off"`, so the auto-installer cannot run twice and wipe the disk (`reboot-mode` is a `HYPOTHESIS` until 9.1-1 installs)<br>• MAC address spoofing off: guests sit on a routed, masqueraded PVE bridge, so every guest packet leaves through PVE's forward path and reaches Hyper-V with PVE's address | operator | `DECIDED (2026-10-06)` | The lab plan's MAC-spoofing step (operator notes, outside the repo) applied to bridged guests only; not used here |
| D36 | Hyper-V rights during the go | elevated run per step / one elevated run through the install | one elevated run carries every step that needs Hyper-V rights: host setup, VM create, install, wait for power-off, checkpoint while stopped, eject the ISO, start, wait for SSH, with a transcript readable by the operator. Later start / stop / checkpoint use Hyper-V Administrators (D26) after the owner's next sign-in | operator: group membership applies at the next sign-in, and signing out ends the session | `DECIDED (2026-10-06)` | Install progress is observed over the network, not with `Get-VM` |
| D37 | Host-side R15 layer (refines R15's "Windows firewall bound to the VM's NAT") | Windows Defender Firewall only / Hyper-V port ACLs + Windows Defender Firewall | • Hyper-V extended port ACLs on the VM adapter: deny RFC 1918, `100.64.0.0/10`, `169.254.0.0/16`, every prefix the host routes through a non-default interface (read at each VM start), and IPv6; allow stateful replies to sessions the host opens<br>• Windows Defender Firewall: block inbound from `10.99.0.0/24` on the internal vEthernet | operator: whether Defender Firewall filters WinNAT-forwarded traffic is unmeasured; a port ACL is enforced by the switch, outside the VM. No prefix is hard-coded beyond public RFC ranges (R16) | `DECIDED (2026-10-06)` | `HYPOTHESIS` until the negative tests run from PVE itself in Phase 1 (positive controls from Windows); runner-class tests stay the Phase 2 DoD |
| D38 | Local paths | — | VM config, VHDX and the install ISO copy under `C:\HyperV\pve01\`, ACL limited to SYSTEM, Administrators and Hyper-V Administrators; downloads and the prepared ISO under `%LOCALAPPDATA%\homelab\`. The rendered answer file and the prepared ISO hold the root-password hash: never in the repo, deleted after the install | operator | `DECIDED (2026-10-06)` | — |
| D39 | SSH keys | one shared key / one per side | two ed25519 keys: Windows `%USERPROFILE%\.ssh\homelab_pve01_ed25519` (operator and owner from Windows) and WSL `/root/.ssh/homelab_pve01_ed25519` (automation); both public keys go in the answer file | operator: Windows OpenSSH refuses key files with WSL-style permissions; each side keeps its own key | `DECIDED (2026-10-06)` | — |
| D40 | Package repository switch and `apt full-upgrade` | ad hoc in Phase 1 / first Ansible role in Phase 2 | first Ansible role in Phase 2 (repos per D31, full-upgrade, reboot); the Phase 1 nested smoke test runs on the installer kernel and again after the upgrade | operator: codified once, proven by the second run's `changed=0` | `DECIDED (2026-10-06)` | Phase 1 DoD (`pveversion` 9.x, nested result) does not depend on the upgrade |
| D41 | Phase 2 OpenTofu state backend | MinIO S3 (`iac/tofu/backend.tf:9`, retired host) / local backend with state encryption | local backend in WSL with OpenTofu state encryption enforced (passphrase in SOPS); the local backend locks the state file; move to the Phase 4 S3 backend with `use_lockfile` | operator: the MinIO endpoint belongs to the retired host and the cache service arrives in Phase 4 | `DECIDED (2026-10-06)` | — |
| D42 | Trust boundary of the workstation (refines G1) | disable other administrator accounts / accept them | accept: the owner uses the machine alone; every local administrator account is inside the trust boundary and can read the age key, the SSH keys and the VM disk | owner, 2026-10-06 (after the secrets review found a second, unused administrator account the owner cannot manage) | `DECIDED (2026-10-06)` | ACLs on the key files limit other non-admin principals only |
| D43 | Hyper-V Administrators, re-confirmed with the full disclosure (refines D26) | keep / decline | keep. Disclosed: membership is not filtered by UAC; any process running as the owner can change or remove the VM's port ACLs, read the VM disk, and is widely reported to be able to reach host-administrator rights (`HYPOTHESIS`, not tested); only the Windows Firewall rule stays outside that reach | owner, 2026-10-06, after the scripts' security review | `DECIDED (2026-10-06)` | `AddOwnerToHyperVAdministrators` in the host config makes the choice reversible without a code change |
| D44 | Ansible / SSH control path from WSL to PVE | WSL mirrored networking / IP forwarding between vEthernets / `ProxyCommand` through the Windows `ssh.exe` | `ProxyCommand` through the Windows `ssh.exe -W %h:%p` (set in the inventory's SSH arguments); OpenTofu's HTTPS to `:8006` goes through an SSH local forward on the same path | operator: row 39 measured the direct path failing and the proxy path working; no host network change and no new listener (D24) | `DECIDED (2026-10-06)` | — |
| D45 | Remote access to the PVE web UI (supersedes D24's "none") | this laptop only / mesh VPN serve TCP forward on the Windows host / Windows as a subnet router | the mesh VPN's serve feature on the Windows host: a TCP forward of the tailnet port 8006 to `10.99.0.2:8006`, so PVE's own TLS reaches the browser end to end (same certificate fingerprint); PVE stays off the tailnet (D20 holds); no subnet route; reachable only from the owner's tailnet devices | owner, 2026-10-06 ("from any machine"); operator chose the narrowest mechanism: one port, no route for the whole subnet, no Windows IP forwarding | `DECIDED (2026-10-06)` | `HYPOTHESIS` that the forward accepts a non-loopback target on the installed mesh VPN client until it runs; rollback is the serve feature's reset command. TOTP on `root@pam` is recommended before regular remote use (J5b) |
| D46 | Layout and N hosts (plan D45; R5.1) | one directory per host / one data file read by every tool, stacks select the host by variable | `iac/inventory/hosts.yml` is the single host data file for Ansible and OpenTofu; a second host is one new entry; OpenTofu stacks select the entry by `var.host` (arrives with the stack PR) | operator: R5.1 says adding a host is a data change, not a code change | `DECIDED (2026-10-07)` | 0021 |
| D47 | One owner per object (plan D46) | firewall as OpenTofu cluster resources / Ansible-templated `.fw` files | Ansible owns OS configuration, its own SSH identity, OpenTofu's API identity and the host/cluster firewall files; OpenTofu owns SDN, guests, guest firewall options and template downloads | operator: cluster firewall endpoints need `Sys.Modify`; keeping them out of OpenTofu keeps its token narrow; the dead-man fits a role | `DECIDED (2026-10-07)` | 0025 |
| D48 | Bootstrap of OpenTofu's API identity (plan D47) | OpenTofu manages its own identity / Ansible creates it | Ansible creates `tofu@pve`, role `HomelabProvisioner` (measured privileges only), pool `homelab`, ACLs, and a privsep token whose secret goes straight into SOPS (`sops set --value-stdin`, never on argv) | operator: the identity that runs OpenTofu is never managed by OpenTofu | `DECIDED (2026-10-07)` | 0026 |
| D49 | Ansible's SSH identity and sshd hardening (plan D48) | keep root over SSH / key-only `automation` with NOPASSWD sudo, root restricted to the jump | `automation` (key-only, NOPASSWD sudo); root keeps only the Windows-side key with `from="10.99.0.1"`; password and keyboard-interactive login off; applied after a fresh second session succeeds, behind a persistent 10-minute dead-man | operator: NOPASSWD sudo is root-equivalent and inside D42's boundary; the dead-man makes a lockout self-healing | `DECIDED (2026-10-07)` | 0023 |
| D50 | Control path (plan D49; refines D44) | per-command `ProxyCommand` arguments with first-use trust / a rendered ssh config outside the repo with the host key pinned | `scripts/iac/render-ssh-config.sh` renders `~/.config/homelab/ssh_config` and `known_hosts` from the inventory; the PVE host's public key is stored SOPS-encrypted (`iac/secrets/hosts/pve01-ssh.sops.yaml`) and pinned with `StrictHostKeyChecking yes`; the jump hop stays the Windows `ssh.exe -W` as root with the Windows key; `scripts/iac/ansible.sh` uses the rendered config | operator: removes `accept-new` first-use trust from the inner hop; the repo carries no host key or fingerprint in clear (R16) | `DECIDED (2026-10-07)` | 0022, 0029 |
| D51 | OpenTofu state layout (plan D50; refines D41) | one shared state / one state per stack and host | `/var/lib/homelab/tofu/<stack>/<host>.tfstate` on WSL ext4; encryption enforced for state and plan; passphrase in `iac/secrets/tofu/<host>-state.sops.yaml`; an encrypted copy on the Windows side after each apply | operator: a stack's state holds only its own resources and secrets; locking on the Windows mount is assumed unsafe | `DECIDED (2026-10-07)` | 0013 |
| D52 | Secrets layout and write path (plan D51) | one secrets file per host / one file per consumer and host, one writer per file | one SOPS file per consumer and host under `iac/secrets/hosts/` and `iac/secrets/tofu/`, each with one writer; values reach `sops` on stdin, never on argv; the host-routed prefixes stay encrypted (`pve01-network.sops.yaml`) | operator: OpenTofu's environment never holds the root password, and one writer per file avoids lost updates | `DECIDED (2026-10-07)` | 0033 |
| D53 | PVE firewall mechanism (plan D52) | classic pve-firewall with security groups / nftables proxmox-firewall (tech preview) / hand-written nftables | classic pve-firewall: ipsets `management`, `public-v4` (two /1 halves with nomatch entries), `host-routed`; security group `guest-egress`; host traffic only from management; persistent dead-man | operator: the PVE docs call the nftables firewall a tech preview not suited for production | `DECIDED (2026-10-07)` | 0027 |
| D54 | Guest network (plan D53) | per-guest bridges / one SDN simple zone with SNAT | SDN simple zone `hlab`, vnet `guests` with `isolate_ports`, subnet `10.99.16.0/24` (gateway `.1`), SNAT, static addresses, no DHCP, applied by `proxmox_sdn_applier`; away from `10.99.0.0/24` (D22) | operator: one declared network for probes and runners; no new listener on pve01 | `DECIDED (2026-10-07)` | 0030 |
| D55 | R15 proof design (plan D54) | host-side checks only / in-guest probes, red first, paired controls, across restarts and reboots | throwaway LXC + VM with the runner-class policy; red-first under `pve-firewall stop`; every negative paired with a positive control; an egress positive every run; phases baseline, container restart, PVE reboot, host reboot; drift check of per-guest options | operator: a blocked probe without a control proves nothing, and a check that never ran red proves nothing | `DECIDED (2026-10-07)` | 0031 |
| D56 | Probe control channel (plan D55) | guest agent / provider SSH snippets / SSH from pve01 with a key generated there | SSH from pve01 with a throwaway key that never leaves it; one guest inbound rule tcp/22 from the gateway only | operator: every probe negative is guest-originated egress, so this inbound allow does not change what is tested | `DECIDED (2026-10-07)` | 0032 |
| D57 | IaC CI scope (plan D56) | everything in hosted CI / lint + Molecule in CI, host changes proven locally | hosted CI: tofu fmt/validate per root module, tflint, ansible-lint, syntax-check, Molecule for `base`, `tests/isolation/test-*.sh`; host changes (converge, plan/apply, R15) proven locally and pasted into PR bodies | operator: hosted runners cannot reach the lab and must not | `DECIDED (2026-10-07)` | 0024 |
| D58 | Assets of the retired host (plan D57) | port to PVE 9 / keep dormant / retire and cite by SHA | retire: bootstrap, cache policies, import scripts, old Ansible tree, its two scripts and CI job; the egress domain list and the bucket-scoped policies stay readable at master `179f826` | operator: they target the retired host, compete with pve-firewall or disable host-key checking; dormant files mislead | `DECIDED (2026-10-06)` | 0020 |
| D59 | Restore points of the PVE VM (plan D58; refines D23) | checkpoints of a running VM / `Export-VM` copies / none / checkpoints only while Off through one script action | `Invoke-PveVm.ps1 -Action Checkpoint`: Off only, name valid and unused, no DVD media, free space above the floor (worst case only warns), polled read-back, the checkpoint removed if it recorded a running state or media | operator: a running VM was suspended by host standby; standard checkpoints write memory to disk; measured restore is 16 s to SSH | `DECIDED (2026-10-06)` | 0019 |
| D60 | TOTP for `root@pam` and notifications (plan D59) | TOTP now / TOTP before regular remote use | TOTP is an owner step in the web UI (enrolment shows the secret to a human, about 2 minutes); the notification target waits for Phase 7 | owner: enrolment cannot be delegated | `OPEN (owner)` | — |
| D61 | Requirements publication (plan D60) | publish this document as is / publish a redacted copy | `docs/platform/requirements.md` is built from this document by a sanitizing builder: the row-22 prefixes, the row-23 addresses, the workstation and user names become labels; local paths are removed; the unredacted copy stays operator-local; the repository copy is canonical once merged | operator: R16 and a public repository | `DECIDED (2026-10-07)` | 0034 |
| D62 | Hyper-V socket transport inside the PVE guest (new) | leave `hv_sock` loaded / block the module in the guest / also remove the integration devices on the Hyper-V side | block the module (`install hv_sock /bin/false`), unload it; integration devices stay | operator: it is a host↔guest channel outside every network control (R15); KVP/VSS are unused (ADR 0019) | `DECIDED (2026-10-07)` | 0028 |
| D63 | Owner of the storage definitions in Phase 2 (new; narrows the Phase 2 line "OpenTofu for storage") | OpenTofu manages storage / storage stays as the installer made it | storage stays as the installer made it: `local` (iso, vztmpl, backup, import) and `local-lvm` (guest disks) serve every Phase 2 need; OpenTofu reads them; Phase 3 (images) and Phase 4 (cache) name an owner | operator: changing storage definitions needs `Datastore.Allocate` on `/storage`, which also deletes any volume; the token's least privilege (D48) excludes it | `DECIDED (2026-10-07)` | 0035 |

### Rejected options and why

- **Rejected: repair and keep the old host.**
  - The owner retired it.
  - PVE 8.4 has been out of support since 2026-08-31.
  - The CTs' 12 GB disks filled repeatedly (runs [37347994171](https://github.com/ugritchaichana/booth-homelab/actions/runs/37347994171), [37348137987](https://github.com/ugritchaichana/booth-homelab/actions/runs/37348137987)).
- **Rejected: Kubernetes plus a Kubernetes-based runner controller on the laptop.** RAM is reserved statically within a fixed budget, and it adds one more layer to operate.
- **Rejected: Docker in LXC by default.** Proxmox does not support it (row 13); see D9.

---

## 7. Security / Risk / Rollback

> Phases 1–2 affect one laptop: WSL2 and Docker Desktop may break, and no environment is reached. Detection is immediate at the regression gate. Rollback takes about 15 minutes, with the owner accepting UAC and a reboot.

### 7.1 Security pre-flight (answer every row; `N/A` allowed; never delete a row)

| Question | Answer | If yes, what else |
|---|---|---|
| Touches secrets / credentials / tokens? | `yes`:<br>• PVE root password<br>• PVE API tokens (provisioner / controller / backup)<br>• GitHub fine-grained tokens: Administration RW for JIT minting, Administration read for the router<br>• cache root and reader/writer keys<br>• SOPS age key<br>• SSH keys | • Generate locally; never print.<br>• Store per Q6.<br>• By-value scans of every PR body, log and commit.<br>• gitleaks in CI.<br>• Never reuse the five old values. |
| Touches IAM / permissions / roles? | `yes`:<br>• Windows admin (UAC for Hyper-V)<br>• PVE roles/ACLs per token<br>• token scopes<br>• bucket policies | • Each token gets only the paths and privileges its role needs, with the reason in an ADR.<br>• Tokens are fine-grained, scoped to the Q3 repo, with only the Administration level needed.<br>• 2026-10-06 (D26): the owner's account joins Hyper-V Administrators, owner-accepted |
| Real customer data into logs / artifacts / reports? | `no` — sample apps with synthetic fixtures | N/A |
| Gives untrusted code a path into private networks? | `yes` — runners execute public-repo code on a host that routes 7 VPN prefixes, tailnet peers and a home LAN | • R15: two isolation layers (PVE firewall + Windows firewall).<br>• Proven by negative tests before the first runner registers.<br>• D17. |

### 7.2 Blast radius estimate (Phases 1–2; Phases 3–8 record their own before starting)

| Dimension | Estimate at opening | Actual at closing |
|---|---|---|
| What breaks, how many | 1 laptop · 2 daily-use components (WSL2, Docker Desktop) · 0 repo CI (old runners still registered) | 0 daily-use components broken: regression gate green at the end of Phase 1 (row 40) and after the last laptop reboot WSL answers in 1.8 s and Docker `hello-world` exits 0 with the VM running (row 53) · 0 repo CI: nothing merged, work lives on PR branches · inside the PVE VM: 3 converge runs failed closed and 1 fired the firewall dead-man, which restored the previous state on its own (row 46) |
| Furthest environment | `none (CI / local only)` | `none (CI / local only)`: the laptop, its PVE VM and CI on PR branches |
| Time to detect | immediately (post-reboot regression gate) | immediately: every host defect stopped its own run at the failing task or assertion (converge runs 1, 2 and 5; two OpenTofu 403s; the state-copy path check) |
| Time to roll back, and who | 15 minutes · `needs approval` (owner accepts UAC + reboot) | no rollback needed; the firewall dead-man restored the host by itself once (row 46); a checkpoint restore + start takes about 16 s and needs no approval; Phase 2 needed no UAC prompt and one owner reboot (the R15 after-reboot proof, row 52) |

**If time to detect exceeds time to roll back, add signal before starting, not a bigger rollback plan.**

### 7.3 Risk / rollback

| Risk | Signal | Rollback |
|---|---|---|
| Enabling Hyper-V breaks WSL2 / Docker Desktop | `wsl -l -v` no longer lists `docker-desktop`, or Docker Desktop fails to start | `DISM /Online /Disable-Feature /FeatureName:Microsoft-Hyper-V-All`, then reboot. Never use "no hypervisor detected" as the rollback check: VBS keeps a hypervisor running |
| The VHDX fills C: | `Get-Volume C` shows < 20 GiB free | Cap the VHDX at creation. Remove with `Remove-VM` and delete the VHDX |
| Static RAM starves daily work (20 GiB static per D19 leaves about 4.5 GiB at row 28's load) | Windows free RAM < 4 GiB under use | Lower the VM's RAM (`Set-VMMemory`) or stop the VM |
| Nested KVM unavailable | `egrep -c "vmx|svm" /proc/cpuinfo` = 0 | D9: Docker jobs go to hosted; nothing else breaks |
| ISO fails to boot | Installer cannot find the CD, or the keyboard is dead | Use 9.1-1 (D8) |
| Checkpoints fail for a nested-virtualization VM | `Checkpoint-VM` errors, or the restored VM does not boot | Checkpoint only while the VM is stopped; otherwise `Stop-VM` and copy the VHDX. `HYPOTHESIS` until Phase 1 |
| Runners reach private networks | An R15 negative test succeeds instead of failing | Register no runner until every negative test fails. If runners exist, stop the pool at once (`pct stop`, stop the controller) |
| A full 140 GiB VHDX leaves C: at about 20.9 GiB (SUPERSEDED 2026-10-06 by D19: 128 GiB cap, about 28 GiB left after the ISOs) | C: < 20 GiB (Windows-side check), or PVE disk > 85% (criterion 3.2) | • Cache eviction within budget<br>• Remove old template versions<br>• `Optimize-VHD` while the VM is stopped |
| Fork PRs reach the old runners before cutover (row 27) | A fork PR's job runs on `pve-runner-01` | • Fastest: the owner sets fork PR approval to "all external contributors" now.<br>• In Phase 6 the router sends forks to hosted (D17). |

Before Phase 6, which touches shared CI, run a risk assessment and summarize its result here.

---

## 8. Evidence to close

> Close when:
> - the timed rebuild is green
> - Q7 holds for 5 consecutive runs
> - every runner is ephemeral
> - the scorecard holds the evidence

| # | What must be proven | Evidence from | Status |
|---|---|---|---|
| T | **Test first** — every new piece must be shown able to fail:<br>• controller unit tests written red first<br>• mutation tests of the queue, scaling and cache-key logic<br>• the stale-binary test, red on current code before the fix<br>• IaC checked by `tofu test` and Molecule | `controller/` tests, `standard/tests/`, run URLs | `not yet` |
| P | **Performance** — full-suite wall-clock and queue-to-start | Baselines: run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969) (hosted, 71 s) and run [37341728563](https://github.com/ugritchaichana/booth-homelab/actions/runs/37341728563) attempt 2 (self-hosted, 174 s), vs runs after cutover | `not measured` |
| 1 | R1: PVE 9 here within budget; daily work unbroken | `pveversion`, `Get-VM`, `Get-Volume`, `wsl -l -v` | `done 2026-10-06` (rows 35, 36, 40); after-reboot recheck pending |
| 2 | R2: timed rebuild from zero via the runbook is green | criterion 3.4 evidence | `not done` |
| 3 | R3: flavor catalog test passes; plan sizes correctly | test + `tofu plan` | `not done` |
| 4 | R4: plan 0; second Ansible run `changed=0`; IaC CI meets criterion 2.5 | run URLs | `not done` |
| 5 | R5: N-host inventory, scoped ACLs, two template versions, clones removed after jobs | `pveum acl list`, logs | `not done` |
| 6 | R6: every unit is `workflow_call`; callers only `uses:` | actionlint + checker script | `not done` |
| 7 | R7 + R8: Q7 targets, load test, priority / cancellation, hit ratio | controller logs + run URLs | `not done` |
| 8 | R9: dependency rule enforced and failing on violation | lint / test | `not done` |
| 9 | R10: portability proof on a non-Proxmox host | run URL | `not done` |
| 10 | R11: every master commit came through a PR | `gh pr list --state merged` vs `git rev-list` | `not done` |
| 11 | R13: gitleaks 0; 0 by-value matches against old values | CI output + scan script | `not done` |
| 12 | R15: every negative test fails, before and after reboots | output from inside runners, stored as criteria 1.3 / 1.5 evidence | `not done` |
| 13 | R16: deny-list grep = 0 over repo, open PR branches and PR bodies; no non-English text in repo docs | grep output | `not done` |

**Above the `P` row: never buy speed with a false green.** That means no narrowing of checks, no unskipping to pad a denominator, and no soft-fail.

---

## 9. Change log

> Opened 2026-10-06, reached `AGREED` the same day, and was rewritten in English, organization-neutral, that night.

| Date | Change | Why |
|---|---|---|
| 2026-10-06 | Opened (in Thai) | The owner asked for a complete requirements document before implementation (R12) |
| 2026-10-06 | Added R15, Q15, rows 22–26, and the restore-point rule in R13 / 7.3 | Review before asking: the host routes VPN prefixes, and checkpoints may not work for nested VMs |
| 2026-10-06 | Closed Q1–Q7 and Q15; added D13–D18 | The owner answered two rounds of questions |
| 2026-10-06 | Added row 27, and the disk-floor and fork-PR risks to 7.3 | The 140 GiB budget leaves C: at about 20.9 GiB; the routing expression sends fork PRs to self-hosted |
| 2026-10-06 | Rows 26–27 `CONFIRMED` from GitHub docs; status `AGREED`; Phase 1 gained the resume-prompt step | Blocking questions closed and 7.2 filled; knowledge must survive the session cut (R2) |
| 2026-10-06 | Rewritten in English. Organization references removed from: the header owner, the R3 and R5 quotes, Q5, 2.2, D1, D2, the rejected options and the R15 wording. Added R16 and 2.1 row 13. The Thai original is kept in the operator notes (outside the repo) | Owner: a neutral homelab baseline, full English (R16) |
| 2026-10-06 | R11 addendum: the vendor-specific agent guide (removed in #56) retired, agent guidance vendor-neutral in `AGENTS.md`. R16 DoD reading fixed before judging: master by full tree; each open PR by its own additions (diff vs merge-base, commit messages included) plus title/body; the scratch merge of master + every open PR by full tree. Full-tree 0 per PR branch follows once the owner merges and the branches are updated from master | Owner instruction in the second session; each PR branch inherits master's lines until then |
| 2026-10-06 | Owner answers, second session: (1) add a one-line pointer file importing `AGENTS.md`; (2) the fork PR approval setting waits — focus first on finishing the neutral repo, which is not integrated with any organization; (3) Phase 1 is not a go — the owner wants to settle Phase 1 details first | Owner direction; the row-27 fork-PR risk stays open until the owner sets the approval or Phase 6 routes forks to hosted |
| 2026-10-06 | Phase 1 discussion: rows 28–31 measured; D13 SUPERSEDED by D19 (12 vCPU / 20 GiB / 128 GiB); D20 PVE off the tailnet; D21 VM starts on demand; D22 NAT subnet; D23 Phase 1 mechanics; age-key backup moves to Phase 1. Phase 1 is still not a go | Measured RAM and disk contradicted the Q1 budget; the owner chose the options |
| 2026-10-06 | Published in the repository as `docs/platform/requirements.md`, sanitized for a public repo: host names, network prefixes, operator-local paths and vendor names removed (R16) | The repo copy becomes canonical (Phase 2) |
| 2026-10-06 | Phase 1 grill G1–G9: rows 32–33 measured (personal unmanaged laptop; elevation works); D24–D32 decided (no remote access yet, manual VM start, Hyper-V Administrators, one Memory Integrity test, scripts never reboot, key backup in a password manager, no owner review of scripts with compensating controls, no-subscription repo, one go for Phases 1–2). Phase 1 is still not a go | Owner asked to be grilled one question at a time |
| 2026-10-06 | Row 34: the owner enabled Hyper-V outside the scripts; the operator re-checked the host and the regression gate (green). The Phase 1 enable step stays in the repo script for reproducibility (R2), as an idempotent no-op on this host. Phase 1 is still not a go | Owner asked for a recheck after enabling Hyper-V |
| 2026-10-06 | **Owner go for Phases 1–2** (about 12:55 ICT), per D32. Owner-only steps during the go: one batched UAC for the elevated host script, and the age-key backup to the password manager before the PVE install (D29). A merge-queue / runner-pool scope discussion ran the same day; its answers live in the operator notes and become a requirement only after the owner places it in the plan | Owner: "do Phases 1–2 on my machine now" |
| 2026-10-06 | Operator decisions D33–D41 recorded before any Phase 1 script is written (toolchain home, install filesystem, VM mechanics, rights timeline, host-side R15 layer, paths, SSH keys, upgrade via Ansible, Phase 2 state backend). Phase 1 line "tailnet access" is superseded by D20 / D24. The first install has no prior state, so its R13 restore point is the reproducible installer; the first checkpoint is taken while the VM is stopped right after the install (D36) | Document first: mechanics settled before the work starts |
| 2026-10-06 | Row 14 RULED OUT as worded (Microsoft states no static-memory requirement; quote recorded). Two independent security reviews of the Phase 1 scripts and secret handling: 0 findings block the install; one blocks runner registration (host-routed prefixes harvested only at start) and is fixed in part (persistent local deny list, fail-closed egress interface, refresh action) with the network-change trigger still required before any runner. Owner answers: D42 (trust boundary includes every local administrator), D43 (Hyper-V Administrators kept with full disclosure) | Reviews run as the compensating control of D30 |
| 2026-10-06 | Phase 1 DONE WHEN met (rows 35, 36, 40): PVE 9.1.1 installed by the repo scripts (PR #58), nested KVM PASS with Memory Integrity on, regression gate green, first restore point taken. Run 1 failed closed on an ACL shape the switch rejects (row 37); a probe measured the accepted shapes and run 2 succeeded. R15 host-side layer measured from PVE (row 38); per-plane tests, read-back and after-reboot tests wait for the owner's reboot (group membership). D44: Ansible reaches PVE from WSL through `ProxyCommand` (row 39). An incident during the key backup (the first age key exposed in a chat) was answered by rotating the age key and the root password before the install | Owner go D32; Phase 2 follows in the same go |
| 2026-10-06 | Phase 2 started: D40 role applied (row 41, PR #59); D45 remote UI through the host (the mesh VPN serve feature + loopback `portproxy`, measured working); R17 added and ADRs 0001–0018 written for every decided row (PR #60); Phase 2 plan written (operator notes, 21 jobs, 10 PRs; its proposed decision numbers start at D46). Owner reboot pending (Hyper-V Administrators, R15 after-reboot tests) | Owner asked for real Proxmox changes, remote UI access and ADRs |
| 2026-10-07 | Session 2 after the owner's reboot: rows 42–45 measured (R15 after reboot incl. the elevated Test 5 rows; D40 proven from the fresh install; host facts; checkpoint action live, including a stale read-back found only by the live run). D58 and D59 decided with ADRs 0020 and 0019. Phase 2 PRs #61–#63 opened as one chain on #60 (each adds an ADR index line); #59 converted to draft and superseded by the Ansible host-roles PR, which re-proves the role from `post-install`. Plan decision numbers D45–D60 map to D46–D61. Merge order for the owner: #57 (rebuilt) → #58 → #60 → #61 → #62 → #63; #59 not merged | Owner: continue phase by phase with a 9-phase overview table after each step |
| 2026-10-07 | Phase 2 DONE WHEN met: rows 46–54 measured on the host and in CI (converge `changed=0`, plan 0, R15 in five phases on both guests incl. after the laptop reboot, CI green at every chain head); 7.2 "Actual at closing" filled; decision rows D51, D52, D60, D61, D63 added (D63 narrows "OpenTofu for storage": storage stays as the installer made it); D50 also cites ADR 0029; the section-6 count corrected. ADRs for D52, D61 and D63 follow in one PR | Independent DoD audit: all four clauses met; the remaining gaps were records, not host state |

### Owner actions (besides merging)

| When | Action | Why |
|---|---|---|
| Now (no need to wait) | Set fork PR approval to "all external contributors": Settings → Actions → General → "Fork pull request workflows from outside collaborators" | Closes the row-27 gap until cutover. Deferred by the owner on 2026-10-06: finish the neutral repo first |
| Before Phase 1 | Give the go for Phase 1 | R12 is met; work starts on the owner's go |
| Phase 1 | Accept the UAC prompt for the Hyper-V and VM scripts; reboot when convenient | The shell is not elevated (row 8) |
| Phase 2 | Keep a backup copy of the age key off this machine | D12: losing the machine would lock every secret. SUPERSEDED 2026-10-06: moved to Phase 1 (D23) |
| Phase 1 | Keep a backup copy of the age key off this machine, before the PVE install | D23: the root password is stored per Q6 from the first boot |
| Phase 5 | Create two fine-grained tokens scoped to `booth-homelab`:<br>• Administration read/write for the controller (JIT minting)<br>• Administration read for the router (pool availability) | D14, D15: token creation is an account setting |
| Phase 6 | Give an explicit go to deregister the old runners | Section 2.1 row 11 |
