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
| 14 | Hyper-V nested virtualization needs static memory, so the VM's RAM is reserved while it runs | `HYPOTHESIS` | Microsoft URL to cite before Phase 1 |
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
- **DONE WHEN:**
  - `pveversion` shows 9.x.
  - The nested KVM result is recorded, pass or fail; on fail, D9 applies.
  - The regression gate is green.
- **Proof:** outputs of the verification checklist in the operator notes (outside the repo), stored as evidence.

### Phase 2 — IaC foundation and security baseline

- **Do:**
  - Clean repo layout with provider adapters, and an inventory of N hosts.
  - Secret store per Q6.
  - OpenTofu (`bpg/proxmox`) for storage, network, users, tokens and ACLs.
  - State backend with locking.
  - Ansible baseline: hardening, firewall including R15, time, logs.
  - IaC CI per criterion 2.5.
  - Publish this document in the repo (e.g. `docs/platform/requirements.md`); the repo copy becomes canonical.
- **DONE WHEN:**
  - Plan returns 0 after apply.
  - The second Ansible run reports `changed=0`.
  - Every R15 negative test fails.
  - CI is green.
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

> 16 decisions made, 13 of them by the owner. 2 left for design: D10 (controller) and D11 (language). D1 and D2 were reworded on 2026-10-06 to remove organization references (R16); their substance is unchanged.

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
| Touches IAM / permissions / roles? | `yes`:<br>• Windows admin (UAC for Hyper-V)<br>• PVE roles/ACLs per token<br>• token scopes<br>• bucket policies | • Each token gets only the paths and privileges its role needs, with the reason in an ADR.<br>• Tokens are fine-grained, scoped to the Q3 repo, with only the Administration level needed. |
| Real customer data into logs / artifacts / reports? | `no` — sample apps with synthetic fixtures | N/A |
| Gives untrusted code a path into private networks? | `yes` — runners execute public-repo code on a host that routes 7 VPN prefixes, tailnet peers and a home LAN | • R15: two isolation layers (PVE firewall + Windows firewall).<br>• Proven by negative tests before the first runner registers.<br>• D17. |

### 7.2 Blast radius estimate (Phases 1–2; Phases 3–8 record their own before starting)

| Dimension | Estimate at opening | Actual at closing |
|---|---|---|
| What breaks, how many | 1 laptop · 2 daily-use components (WSL2, Docker Desktop) · 0 repo CI (old runners still registered) | |
| Furthest environment | `none (CI / local only)` | |
| Time to detect | immediately (post-reboot regression gate) | |
| Time to roll back, and who | 15 minutes · `needs approval` (owner accepts UAC + reboot) | |

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
| 1 | R1: PVE 9 here within budget; daily work unbroken | `pveversion`, `Get-VM`, `Get-Volume`, `wsl -l -v` | `not done` |
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
