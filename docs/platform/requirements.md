# Platform v2 Requirements — a neutral homelab CI baseline on Proxmox VE 9

| | |
|---|---|
| Status | `AGREED` |
| Owner | repository owner |
| Operator | an AI coding agent |
| Canonical copy | This file is the canonical copy of the platform-v2 requirements once merged. |
| Opened | 2026-10-06 |
| Last updated | 2026-10-08 |
| Target repo | `ugritchaichana/booth-homelab` |
| Links | [`standard/README.md`](../../standard/README.md) (#55) · PR #48–#56 · run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969) |
| Single goal | **This workstation runs Proxmox VE 9, rebuilt entirely from code, and runs the repo's CI on single-use runners that scale with the queue — faster than the 71 s hosted baseline, with no false green.** |

Document rules:
- **Never delete earlier content.** When a decision changes, mark it `SUPERSEDED` and append the new one.
- Every requirement and decision carries a date.
- The project is a **neutral homelab baseline**. It names no employer or organization, and its artifacts are in English (R16).

---

## 0. One-page summary

> A new CI platform on this laptop replaces the retired host: 20 requirements, 9 phases. Phases 0-4 are done; Phases 5-8 are handed off (R19 amended).

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

- **Raw request:** "Coding style is clean architecture plus established industry best practice."
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

### R18 — A handoff-ready deliverable; the owner does not operate it (2026-10-07)

- **Raw request:** "From now on I am not the one who operates this in production. The goal is to implement, collect the knowledge, test and measure, and build the docs, the runbook and everything else, then hand it over to another team's technical lead, who continues it themselves."
- **Restated:**
  - This machine is the reference implementation and test bed, not production.
  - Each phase delivers: the code; raw measured evidence; runbook steps that someone who was not here can execute; ADRs; named gaps.
  - No runbook step assumes the owner. A manual step names the role that performs it and the exact command.
  - Host-specific layers (Hyper-V, Windows firewall, the laptop's networks) stay separated from the portable core (Proxmox roles, OpenTofu stacks, templates, controller, workflows), so an adopter can drop the host layer.
  - The repository stays neutral (R16); an adopter maps it to their environment in a fork (R5's raw request).
- **Passes when:**
  - A reader who was not part of the work rebuilds the platform from the runbook alone (Phase 8 timed rebuild).
  - Every measured claim in the docs links to a raw log or a run.

### R19 — Release definition of done (2026-10-07)

- **Raw request (translated):** "The DoD now: the system works completely, every point tested in happy, bad and edge cases as thoroughly as can be thought of, everything finished on my machine. When this passes you may merge, update every document in the repository to the latest state and clear all the debt the previous agent left; then build the documents that prepare others to build it in production. When the documents are done, this release is finished. Run it to the end fully autonomously, with regular checks, still in fast mode."
- **Restated:**
  - Every component the platform ships (host roles, guest network, templates, cache, controller, workflows, observability, runbook) has tests for the happy path, the failure paths and the edge cases that can be identified, and each runs green on this machine.
  - Every proof runs on this laptop (Hyper-V, pve01, WSL, guests); no external device or host is required for this release.
  - After that gate: the PR chain is merged (the owner authorized merging; the harness blocks merge commands for the operator, so the operator prepares the ordered merge commands and the owner runs them); every document in the repository is brought up to date; the previous agent's debt is inventoried and cleared (fixed, retired, or recorded with a reason).
  - Then a handoff package for a team that builds it in production (R18).
- **Passes when:** the release audit finds a happy/bad/edge test for every component with a green run on this machine, the PR chain is merged, a debt inventory shows every item closed or recorded, and the handoff documents exist.
- **Amended 2026-10-07 (owner):** the release covers Phases 0–4; Phases 5–8 are handed off (change log).

### R20 — The repository holds the results, the knowledge and the code (2026-10-07)

- **Raw request (translated):** "This repository will keep every result together with the knowledge and the codebase, so it is ready to be developed further and easy to review."
- **Restated:**
  - Measured evidence lives in the repository, not only in the operator's notes: each phase publishes its raw outputs under `docs/evidence/<phase>/` with an index saying what each file proves.
  - Published copies are sanitized by value: a local, git-ignored map turns real non-lab addresses, machine names and user names into labels; secrets never enter a log in the first place. A check flags (never rewrites) any remaining address outside the lab range, because a pattern-based mask once rewrote a package version.
  - The raw file stays on the operator's machine; the index records the sha256 of the raw and of the published file.
  - Knowledge lives in `docs/knowledge/`: real-host defects and their fixes, lessons, and the test catalogue (what each test proves, how to run it).
  - `docs/platform/requirements.md` cites repository paths or run ids for every measured row.
  - Phases 1–3 are backfilled the same way.
- **Passes when:** every measured row in `docs/platform/requirements.md` resolves to a repository path or a run id; the evidence index lists a sha256 pair per file; the neutrality and secret scans over `docs/evidence/` return 0.

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
| 18 | The restore bumps only files changed since `HEAD~1`, on top of `latest.tar.zst`, which records no SHA. A multi-commit push may therefore reuse stale binaries | `RULED OUT` as worded (2026-10-07, row 64): as shipped the untouched `.pdb` outputs force recompilation, so the script restored bytes but no stale binary; the defect class reproduces once every output is touched and the commit id is left out of the version | `scripts/ci/cache-restore.sh:123-128` |
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
| 35 | Phase 1 elevated run 2 (2026-10-06 15:53–16:02 ICT, exit 0): 18 port ACLs read back and the adapter connected; the unattended 9.1-1 install finished in 459 s and powered the VM off (`reboot-mode = "power-off"` works on 9.1-1); ISO ejected with read-back; checkpoint `post-install` taken while Off without the ISO; first cold start: TCP 22 answered 18.1 s after `Start-VM`; ISO copy deleted | `CONFIRMED` | transcript `docs/evidence/phase1/New-PveHost-20261006-155339.log` |
| 36 | `pve-manager/9.1.1/42db4a6cf33dac83 (running kernel: 6.17.2-1-pve)`; `systemd-detect-virt` = microsoft; `egrep -c "vmx\|svm"` = 12; `/dev/kvm` present; `kvm_amd nested` = 1. Nested KVM works with Memory Integrity on, so D27's test is not needed and D9's VM class is available | `CONFIRMED` | docs/evidence/phase1/j8-results.md (line 69); SSH from Windows, 2026-10-06 16:03 ICT |
| 37 | Hyper-V extended port ACLs on this host: a stateful rule is accepted only for TCP or UDP (ICMP, `ANY` and no protocol are rejected with 0x80070057 when the adapter connects); a stateful Deny is rejected; weight 65535 is accepted, 100000 rejected. Run 1 (15:04) failed closed on this before the VM ever started | `CONFIRMED` | probe on a throwaway, never-started VM, `docs/evidence/phase1/acl-probe-20261006-152843.log` (the install replay reproduced the error exactly) |
| 38 | R15 host-side layer measured from PVE (no runner exists): guest to the host (445/135/139), the home router (80/53), the host's Wi-Fi address, its tailnet and mesh-VPN addresses and the mesh DNS server are all dropped (timeout), each paired with Windows reaching the same target; HTTPS and DNS via 1.1.1.1 work; ICMP to the internet fails by design (stateful TCP/UDP only); IPv6 has no route. Not measured: the two harvested host-routed prefixes (no host in them was reachable even from Windows at the time), UDP to the host, and each plane alone (needs Hyper-V rights) | `CONFIRMED` / `NOT MEASURED` as stated | `docs/evidence/phase1/j8-results.md` (addresses as labels) |
| 39 | WSL (NAT mode) cannot reach `10.99.0.2` directly (TCP 22 timeout); SSH through `ProxyCommand` with the Windows `ssh.exe -W %h:%p` works | `CONFIRMED` | `docs/evidence/phase1/j8-results.md` W1–W3 |
| 40 | Regression gate with the VM running: WSL Debian boots in 2.3 s; Docker Desktop starts and `hello-world` exits 0; available RAM never below 6049 MB (7051 MB at the end); C: 163.9 GB free; 7 VPN prefixes; both mesh-VPN services Running; host internet OK | `CONFIRMED` | `docs/evidence/phase1/j9-gate.md` |
| 41 | D40 role `pve_repos` (PR #59) applied from WSL through the `ProxyCommand` hop: enterprise and ceph repositories `Enabled: no`, `pve-no-subscription` `Enabled: yes`; pve-manager 9.1.1 → 9.2.21, kernel 6.17.2-1-pve → 7.0.14-20-pve; 0 pending upgrades; second run `changed=0`; nested KVM still PASS on 7.0.14 (svm 12, `/dev/kvm`, nested 1). The first attempt's Ansible process never received the long upgrade's result through the proxy hop (the 214-package upgrade finished on the host); async/poll and keep-alives were added but not yet exercised on a long upgrade | `CONFIRMED` / open item as stated | `docs/evidence/phase1/p2j1-report.md`, lead re-run 2026-10-06 ~17:30 ICT |
| 42 | R15 after the reboot (Hyper-V Administrators active, VM started non-elevated): ACL read-back 18 rules, 0 outside 4000–4999, `::/0` and `ANY` read back, one entry per stateful rule, spoofing Off, guards On, IPv6 binding reads False; host→guest and guest egress rows PASS with paired controls; MAC spoofing (scripted, no console) drops traffic and the restored MAC passes; ACLs removed for 14.8 s and restored to 18; folder ACL 4 ACEs, no inheritance, VHDX carries the per-VM ACE. With the Windows Firewall rule disabled for 10.6 s, the port ACLs alone still block guest→host 445 and the stateful mirror (source port 8006) toward the host, while 1.1.1.1:443 opens. Harvested-prefix row NOT MEASURED (no address inside those prefixes answers even from Windows); guest ICMP to the Internet is dropped by the ACL plane (no stateful ICMP on this switch) | `CONFIRMED` | `docs/evidence/phase1/r15-after-reboot-results.md`, `docs/evidence/phase1/r15-test5-elevated-20261007-002415.txt` |
| 43 | D40 role proven from the fresh install (`post-install` restored): run 1 `ok=8 changed=5 unreachable=0 failed=0` in 254 s including the reboot into 7.0.14-20-pve, the upgrade result returned through the `ProxyCommand` hop; run 2 `changed=0`. A first attempt was invalid: the laptop entered Modern Standby 1 minute in (on battery), suspended the VM and the control process was stopped on resume | `CONFIRMED` | `docs/evidence/phase2/pristine-b-run1.txt`, `docs/evidence/phase2/pristine-b-run2.txt`; Kernel-Power events 506/507 |
| 44 | PVE 9.2.21 host facts: `sudo` absent; sshd `permitrootlogin yes`, `passwordauthentication yes`; pveproxy `*:8006` and spiceproxy `*:3128` on all interfaces, pvedaemon loopback; PVE firewall disabled; `hv_sock` loaded; dnsmasq absent; `local` storage allows `import`; Debian 13 LXC template listed; `/cluster/sdn/zones` POST needs `SDN.Allocate` on `/sdn/zones`, node firewall rules need `Sys.Modify` on `/nodes/{node}` | `CONFIRMED` | `docs/evidence/phase2/host-facts.txt` |
| 45 | Stopped-VM checkpoint action live: refusal while Running (exit 1); first success run created the checkpoint but the immediate `Get-VMSnapshot` read listed it 0 times (stale read, false FAIL); with `-Passthru` + polling by Id: PASS in 6.5 s; duplicate name refused; cold starts after restore 16 s, 16 s, 15.8 s, 15.7 s; disk chain 17.7 GiB with 3 checkpoints | `CONFIRMED` | docs/evidence/phase1/checkpoint-refusals-2026-10-07.txt (refusals re-measured 2026-10-07); PR #61 body |
| 46 | Ansible converge on pve01 (PVE 9.2.21) as `automation` after a root bootstrap (`ok=11 changed=4`). Run 1 failed closed on a missing secret directory (the rescue removed the new token); run 2 failed on a false-positive firewall compile check, and the firewall dead-man fired on the real host and restored the previous state (`restore finished rc=0`). After the fixes: run 3 `ok=129 changed=14 failed=0`, run 4 `ok=113 changed=0`; runs 6–7 on the final state (guest network and probe guests present) and run 8 after the probe teardown `ok=114 changed=0 unreachable=0 failed=0` | `CONFIRMED` | docs/evidence/phase2/converge-site-1.txt, converge-site-2.txt (runs 1-2 fail closed), converge-site-8.txt |
| 47 | Host baseline after converge and after the PVE and laptop reboots: sshd `permitrootlogin without-password`, password and keyboard-interactive off; password login and the control node's key as root → `Permission denied (publickey)`; the Windows break-glass key as root from 10.99.0.1 works; `hv_sock` loaded 0 with `install /bin/false`; IPv6 accept_ra, autoconf and `all.forwarding` 0; pve-firewall enabled/running; the guest-firewall guard timer active, seen stopping a half-created VM (`VIOLATION vmid=9102 … firewall not enabled`) | `CONFIRMED` | docs/evidence/phase2/sshd-baseline-2026-10-07.txt (re-measured 2026-10-07); PR #67 body |
| 48 | OpenTofu token `tofu@pve!provisioner`: `/version` 200, create user 403; effective privileges `/` none, `/sdn/zones/localnetwork` none, `/sdn/zones/hlab/guests` SDN.Allocate/Audit/Use, `/pool/homelab` VM.Allocate/Audit/Config.{CPU,Cloudinit,Disk,HWType,Memory,Network,Options}/PowerMgmt. Two 403s seen only on the host: tags at create (PVE checks tag permission without the pool, so a pool-scoped token cannot tag at create; tags dropped) and `Datastore.Audit` on the disk storage (granted). Deleting a volume needs `Datastore.Allocate` on the storage, which would also delete any volume there and read the storage config: not granted, so the probe teardown needs one operator `pvesm free` per downloaded file | `CONFIRMED` | docs/evidence/phase2/probe-tofu-apply1.txt; PR #67, #71 bodies |
| 49 | OpenTofu host stack: apply "5 added"; `plan -detailed-exitcode` rc 0 after the apply, after the state-copy fix and after the probe teardown; state mode 600 with `encrypted_data` and 0 plaintext `resources`; a concurrent plan → `Error acquiring the state lock`; a wrong passphrase → `decryption failed … message authentication failed`; an encrypted copy written on the Windows side; Ansible state survived a VM restart (firewall on, guard active, `ifquery --check -a` rc 0). Lock and passphrase reds re-run after the laptop reboot with the same result | `CONFIRMED` | PR #68 body; `docs/evidence/phase2/tofu-reds.txt` |
| 50 | Guest network: SDN zone `hlab`, vnet `guests` 10.99.16.1/24 with port isolation; SNAT is `-j SNAT --to-source 10.99.0.2` (not MASQUERADE); forwarding is per interface (guests and vmbr0 1) while `all.forwarding` stays 0 | `CONFIRMED` | docs/evidence/phase2/probe-tofu-apply1.txt, probe-tofu-apply2.txt |
| 51 | R15 red-first (pve-firewall stopped), both guests: gateway and management SSH and web console OPEN, so the PVE layer is what blocks those rows; every external row still dropped by the Windows layer; guest to guest direct unreachable and via the gateway dropped (port isolation holds without the firewall) | `CONFIRMED` | docs/evidence/phase2/r15-red-first-lxc.txt, r15-red-first-vm.txt |
| 52 | R15 with the firewall on, per guest (container and VM), 15 negatives and 1 egress positive with paired controls: baseline, after a container reboot, after a PVE reboot and after a laptop reboot each `negatives_blocked=15/15 positives_ok=1/1 egress_curl=200`. Two rows NOT MEASURED in every phase (VPN peer web, harvested-prefix host): no Windows-side positive exists, so a block cannot be told from an absent service | `CONFIRMED` | docs/evidence/phase2/r15-baseline-*.txt, r15-after-pct-reboot-*.txt, r15-after-pve-reboot-*.txt, r15-after-host-reboot-*.txt |
| 53 | After the laptop reboot: VM started non-elevated, SSH 15.8 s after start; ACL read-back 18 (4 stateful rules = 4 entries, `::/0` twice, protocol `ANY`), host rule Block, IPv6 binding False; web UI through the tailnet and through the port proxy 200. Regression gate: WSL 1.8 s, Docker `hello-world` rc 0, 12449 MB RAM free with the VM and Docker running, C: 146.4 GB free | `CONFIRMED` | `docs/evidence/phase2/phase1-carryover-after-host-reboot.txt` (ACLs, rule, IPv6 binding, web UI), `docs/evidence/phase2/controls-after-host-reboot.txt`; start time and regression gate in the operator log |
| 54 | IaC CI (both jobs: Ansible lint, syntax and Molecule; OpenTofu lint, validate and test) green at the current head of every chain PR: #62 37476645272, #63 37476650705, #64 37507733294, #65 37520875620, #66 37520886757, #67 37552511684, #68 37552514424, #69 37552517008, #70 37552520151 (10 passed), #71 37552523015 (10 + 10 passed, probe harness), #72 37552526486, #73 37552529539, #74 37552532600. The repository-wide .NET build is red on #57, #58 and master `179f826` alike (inherited, not Phase 2) | `CONFIRMED` | IaC CI runs 37476645272 to 37552532600, one per PR, listed in the claim |
| 55 | Golden-template builds on pve01 (PVE 9.2.21): lxc-runner about 2 min 15 s, vm-docker about 3 min 5 s per version. The first host runs found seven defects that offline tests with fakes could not, each fixed in a PR: a missing `pvesm` subcommand; an on-change build trigger lost after a failed converge; a 0700 parent directory the guest-facing user cannot traverse; a lagging cluster status that let cleanup destroy a running guest; a sandbox mount of a removed directory; an apt lock held by cloud-init's first boot; the runner's bundled npm config and docs tripping the secret scan. The gates held on the real host: pre-start read-back, the pass marker, the in-guest secret scan | `CONFIRMED` | docs/evidence/phase3/converge-site-1.txt, docs/evidence/phase3/build-weekly-1.txt, docs/evidence/phase3/build-weekly-2.txt, docs/evidence/phase3/build-weekly-3.txt; PR #79, #80, #84 bodies |
| 56 | Two versions per class with manifests, and one-command rollback: after six builds both classes hold exactly two versions, lxc-runner current v6 / previous v5 and vm-docker current v6 / previous v5 (older versions retired after the clone-origin check); a systemd timer fired the weekly rebuild of both classes; `homelab-template rollback` moved `current` back one version and forward again on both classes, exit 0; each version's manifest hashes to the `manifest_sha256` in its template description; `pvesh get /nodes/pve01/storage/local-lvm/content` lists the four template base volumes (8 GiB LXC, 20 GiB VM); thin pool 20.06% data, 2.01% metadata | `CONFIRMED` | docs/evidence/phase3/build-lxc-retention.txt, docs/evidence/phase3/journal-timer-fired.txt, docs/evidence/phase3/proof-rollback-token.txt, docs/evidence/phase3/evidence-rollback-vm.txt, docs/evidence/phase3/evidence-manifests.txt, manifest-exact-*.json |
| 57 | Token boundary after Phase 3: the provisioner token gets 403 deleting a template (`VM.Allocate`) and 403 retagging it, 200 cloning it; pool `templates` holds only the templates; a VM clone's cloud-init drive needs `VM.Config.CDROM` (measured 403, granted on the guest role) | `CONFIRMED` | docs/evidence/phase3/proof-rollback-token.txt, docs/evidence/phase3/evidence-token-more.txt, docs/evidence/phase2/probe-tofu-apply1.txt; PR #77, #83 bodies |
| 58 | Linked clones inherit the template's tags and its guest firewall (rules = the `guest-egress` group, options = the runner-class policy); an LXC config update rejects `ssh-public-keys` (create-only). So consumers resolve templates only among members of pool `templates`, and stacks do not redeclare a clone's firewall | `CONFIRMED` | docs/evidence/phase3/probe-tofu-apply1.txt, docs/evidence/phase2/probe-tofu-apply2.txt; PR #83 body |
| 59 | R15 on clones of both templates, phase baseline: `negatives_blocked=15/15 positives_ok=1/1 egress_curl=200` on the container and the VM (17 PASS, 0 FAIL, 2 NOT MEASURED each). The vm-docker clone runs `docker run hello-world`, exposes no `svm`/`vmx`, has no Docker TCP listener and an unconfigured runner whose user has no sudo. Finding: cloud-init restores the default user's NOPASSWD sudo at a VM clone's first boot (a Phase 5 entry gate) | `CONFIRMED` | docs/evidence/phase3/r15-baseline-lxc.txt, docs/evidence/phase3/r15-baseline-vm.txt, docs/evidence/phase3/evidence-vm-clone.txt |
| 60 | Phase 2 end state held through Phase 3: `site.yml` second run `changed=0`, host stack `plan -detailed-exitcode` no changes; base images are fetched by Ansible with pinned sha512; storage `local` gained `snippets` with its previous content types kept; the weekly rebuild timer is armed (`Persistent=true`). R3 catalog tests run in CI (aws/t3.medium = 2 cores, 4096 MB, 30 GB) | `CONFIRMED` | docs/evidence/phase3/converge-site-7.txt, docs/evidence/phase3/tofu-host-plan-after-phase3.txt, docs/evidence/phase3/evidence-timer.txt; IaC CI run 37560039041 (catalog tests) |
| 61 | Cache network on pve01: the host plan for the second vnet read "3 to add, 0 to change, 1 to destroy" (vnet and subnet `cache` added, only the SDN applier replaced), apply, then "No changes"; `cache` forwarding 1; SNAT `-s 10.99.17.0/24 -o vmbr0` only, and the cache access log shows the runner's own address, so runner-to-cache traffic is not translated; the guard with the per-vnet policy reports ok. The first host converge changed 20 objects; the second applied upstream updates published that day (kernel 7.0.14-20 to 7.0.14-22) and rebooted pve01 by design; the third ended `changed=0`. Nested KVM still on after the new kernel (`nested=1`) | `CONFIRMED` | docs/evidence/phase4/tofu-proxmox-host-plan1.txt, tofu-proxmox-host-apply1.txt, tofu-proxmox-host-final-plan.txt, fw-after-sdn.txt, converge-site-1.txt, converge-site-2.txt, converge-site-3.txt, pve-reboot-kernel.txt |
| 62 | Cache service (bazel-remote 2.6.2 in container 9050): container created stopped and started only after a firewall read-back, service converge `changed=13` then `changed=0`; from a runner clone: anonymous GET 404 then 200 with the written body, anonymous PUT 401, wrong password 401, writer PUT 200, a PUT whose body does not match its digest 500 and nothing stored, DELETE 401; size limit 8 GiB on `/metrics` | `CONFIRMED` | docs/evidence/phase4/converge-cache-1.txt, converge-cache-2.txt, converge-cache-7.txt, cache-api.txt, tofu-cache-service-apply1.txt, tofu-cache-service-final-plan.txt |
| 63 | Cache hit ratio (Q7) with an unchanged lockfile: 20 fresh-workspace runs on a runner-template clone (4 cores, 4 GiB). Run 1 (writer, push to the default branch) missed three times and saved three entries; runs 2–20 (pull-request context, no credential) hit every restore: dependencies 38/38, outputs 19/19. The server access log for the same window: `GET /ac` 200 ×57, 404 ×3; `GET /cas` 200 ×57; all from the runner's address. Per run: dependency restore 6.2–7.5 s, install 1.1–2.0 s, output restore 0.4–0.6 s, build 1.0–1.6 s with CoreCompile skipped. The Prometheus AC counter stays 0 for these lookups when AC validation is disabled; hits are counted from the access log | `CONFIRMED` | docs/evidence/phase4/cache-loop20-results.txt, cache-accesslog-loop20.txt, metrics-before-loop.txt, metrics-after-loop.txt, loop-window.txt |
| 64 | Stale binaries, red first: `tests/cache/test_stale_binaries.sh` on hosted CI with .NET SDK 8 prints `OLD-as-shipped: not stale (pdb mtime forces CoreCompile)`, `OLD+pdb: not stale (the commit id in the generated AssemblyInfo.cs forces CoreCompile)`, `OLD+all-outputs-touched+no-revision-in-version: STALE detected`, `NEW: FRESH`, `NEW: HIT up-to-date (CoreCompile skipped 7/7)`, `PASS`. Row 18 is ruled out for the script as shipped, and the defect class is reproduced once the outputs are all touched and the commit id is left out of the version | `CONFIRMED` | cache CI run 37592628530 |
| 65 | Cache bad paths and edges on the host: a blob corrupted on disk is rejected by the client's digest check (`blob digest dfd353005c2b != manifest c16695b671f1`) and a writer re-save repairs it; service stopped: restore misses in 2003 ms and the build continues; restart: "Loaded 7 existing disk cache items" and hits; two concurrent writer saves of one key both succeed and the next restore hits; a wrong password is refused by an empty-blob credential probe before any upload; LRU eviction with a 1 GiB instance: 40 × 32 MiB written, 32 kept, the 8 oldest unread evicted, a blob read after every write kept. bazel-remote 2.6.2 loaded and served (200) a partially written file after `kill -9` during an upload; a start-time sweep now quarantines it (404 afterwards) | `CONFIRMED` | docs/evidence/phase4/cache-edges-1.txt, cache-edges-2.txt, cache-edges-3-wrongpw.txt, cache-eviction.txt, cache-kill9-check.txt, cache-kill9-after-sweep.txt |
| 66 | R15 with the cache path, from runner clones of both template classes and from inside the cache container. Final baseline: runners `negatives_blocked=19/19 positives_ok=2/2` (cache tcp/8080 reachable; cache tcp/22, the cache gateway's tcp/22 and tcp/8006, and a closed cache port all dropped), cache container `12/12 1/1`. Red-first with the node firewall stopped proves each new row can fail: runners `10/10 11/11` (the gateway ports open, the closed cache port refused), cache container `8/8 5/5`. After a pve01 reboot with every row: runners `19/19 2/2`, cache container `12/12 1/1` (an earlier reboot, before the three cache-vnet rows existed, gave `16/16 2/2`). Before the cache rows existed the runners were `15/15 1/1` with the new group rule in place | `CONFIRMED` | docs/evidence/phase4/r15-baseline-lxc.txt, r15-baseline-vm.txt, r15-baseline-cache.txt, r15-red-first-lxc.txt, r15-red-first-vm.txt, r15-red-first-cache.txt, r15-after-pve-reboot-lxc.txt, r15-after-pve-reboot-vm.txt, r15-after-pve-reboot-cache.txt, pre-cache-r15-baseline-lxc.txt, pre-cache-r15-baseline-vm.txt, pve-reboot-2.txt |
| 67 | Reboots: after a pve01 reboot SSH answered at 43 s, the cache container ran at 45 s and the service at 49 s with its data and every restore kind hit; a container reboot starts the service cleanly after the address wait (`wait-for-address: 10.99.17.10 is configured after 1 seconds`). Two defects were found and fixed on the way: a first start before the address existed (`bind: cannot assign requested address`) and an address check that used `ip`, which cannot open a netlink socket under the unit's address-family sandbox | `CONFIRMED` | docs/evidence/phase4/pve-reboot.txt, cache-ct-reboot.txt, cache-ct-reboot-2.txt |
| 68 | The reusable pipeline with the new cache wiring runs green on the hosted fallback with the cache disabled: every job green, the save jobs skipped outside a default-branch push, the Report prints `Build Cache: disabled (no CACHE_URL)` and each restore reports `miss (no store configured)` with 0 `store unreachable` lines. An earlier run (37597002154) was green too but showed a defect the audit found: the expression `cond && '' || url` always yields the URL because an empty string is falsy, so hosted jobs waited on 2-second connect timeouts; the expression is inverted and a workflow test now rejects that shape and any writer secret outside the cache save steps. The self-hosted path waits for the Phase 5 runners | `CONFIRMED` | SDET CI run 37602620111 |
| 69 | Evidence in the repository (R20): Phases 1–3 published (50 files) and Phase 4; the checker exits 0 and a second, independent by-value scan against the operator map found 0 real values, after it had found three leaks the checker could not see (a user name after a backslash, a deny-listed word inside a command, an operator path), each fixed by extending the map before anything was pushed | `CONFIRMED` | evidence CI runs 37597435239 (tooling, after the allowlist fix) and 37600851460 (Phase 4 evidence); `docs/evidence/*/INDEX.md` |
| 70 | Hardening from the phase-end security review, measured: the writer credential sits only in the environment of the cache client's save steps, which pack artifacts that the same run's build and test jobs uploaded (no install script or build runs beside it); restore extracts only the plan's paths, caps bytes and members, and refuses an interpreter older than the tarfile-filter fixes (3.11.13, 3.12.11, 3.13.4); the container start gate also refuses a second NIC; nine more systemd sandbox directives run in the unprivileged container (`systemd-analyze security`: "Overall exposure level for bazel-remote.service: 2.1 OK"); the evidence checker no longer trusts the checker's own test vectors. Two host findings on the way: re-created probe guests met the previous generation's host keys (now forgotten at key generation), and the guest bridge's IPv6 link-local changed after the SDN re-apply, which made the operator's target file stale | `CONFIRMED` | docs/evidence/phase4/cache-sandbox.txt; hosted SDET run 37602620111; cache CI run 37602586953 (workflow secret test) |
| 71 | Flavor guests on pve01 (D83): `new-guest.sh` planned and created 9501 `demo-lxc-runner-v6` and 9502 `demo-vm-docker-v7` from `aws/t3.medium` (2 cores, 4096 MB, 30 GB). The container clone kept the template's 8 GB disk until a second apply resized it in 23 s, so the wrapper applies twice and requires a settled plan; the provider reads a VM's pool back as empty and the follow-up update failed with 403 Pool.Allocate, so `pool_id` is ignored for VMs. Settled plan "No changes"; with both started the guard reports "ok, 9 guest(s) checked" | `CONFIRMED` | docs/evidence/closeout/guest-plan-lxc.txt, guest-lxc-apply2.txt, guest-apply-vm.txt, guest-settled.txt, guest-start-guard.txt |
| 72 | Guest names say role and source (owner): 9050 `build-cache-debian-13`, 9101 `r15-probe-lxc-runner-v6`, 9102 `r15-probe-vm-docker-v7`; plans in place only; the container hostnames were set with `pct set` first because the provider reboots a running container on a hostname change; settled plans exit 0; `ssh build-cache` works with strict host keys; cache converge `changed=0`; the cache still serves (`NumFiles: 7`) | `CONFIRMED` | docs/evidence/closeout/rename-plan.txt, rename-pct-set.txt, rename-apply.txt, rename-ssh-converge.txt, rename-final-state.txt |
| 73 | Tests added in the close-out (D84), each shown red first: 334 Pester tests for the Hyper-V module (two defects fixed: a culture-sensitive `IndexOf` under th-TH and an empty ACL read-back message; StrictMode exposed two property reads); offline tests for roles `pve_host` and `hyperv_guest` with two new input guards; the cache client at 124 tests with the dependency rule over every module; a tar member guard for the writer jobs | `CONFIRMED` | hyperv-ci run 37628499263; PRs #104, #105, #106, #107 |
| 74 | Line and branch coverage with regression floors (D84, D88): cache client 89.38% (floor 86, cache-ci run 37630718473), evidence publisher 94.75% (floor 94, evidence-ci run 37630718263), scorecard 89.52% (floor 89, run 37631138877), Hyper-V module 99.26% under pwsh 7 and 99.01% under Windows PowerShell (run 37628499263); shell by kcov, local only: `new-guest.sh` 97.83%, selector 80.68% | `CONFIRMED` | docs/knowledge/coverage.md; docs/evidence/closeout/coverage/ |
| 75 | Owner-authorized security steps (D89), read back from the GitHub API: the two retired runners deregistered (runners `total_count=0`); fork pull-request approval `all_external_contributors`; environment `cache-writer` limited to the branch `master`; the writer password rotated (environment secret updated 2026-10-08T03:39:22Z) and converged on the cache host (changed=2, then changed=0 on a second run); three stale wiki pages removed. Hyper-V checkpoints taken before the rotation still hold the old password (none taken after: a checkpoint needs the VM off, D86) | `CONFIRMED` | docs/evidence/closeout/owner-gaps-readback.txt; docs/evidence/closeout/rotate-converge-1.txt, rotate-converge-2.txt |
| 76 | Lab accounts (D92) measured on the host: second playbook run `changed=0` on the host and the three containers; the probe VM over its control key; VM 9502 by vendor snippet at boot, read from a read-only disk snapshot (root and guest passwords match, guest in no administrative group). Independent checks 26 of 26 PASS: `root@pam` 200 with the new password and 401 with the previous one, `guest@pve` 200, reads 16 resources, 403 on a config change, a stop and a user create, privileges only `*.Audit` plus `VM.Console`; in each container and the probe VM the guest cannot write `/etc` and holds no administrative group or docker. Two host-only findings: the provider plans a replacement when vendor data is added to an existing VM (avoided with `qm set` plus a refresh-only apply), and `runcmd` in new vendor data never runs on an existing VM (`bootcmd` used) | `CONFIRMED` | docs/evidence/closeout/lab-accounts-verify.txt; lab-accounts-run1.txt, lab-accounts-run2.txt; lab-accounts-guest-plan.txt, lab-accounts-guest-plan2.txt |
| 77 | CI on the Proxmox runner (D93) measured: three instances online behind the job-started hook (13 offline cases, two mutants caught); a second `ci-runner.yml` run `changed=0`; a drifted installed file makes the next run restart all three through the handler and they return `online`; the user `runner` has no sudo and the container is unprivileged; restores on the runner hit: NuGet 71.8 MB in 2.7 s, `node_modules` 28.7 MB in 4.9 s (run 37746603237); `python3 -m venv` fails in the container (no `python3-venv` in the template). `sdet-ci.yml` wall time from dispatch runs, Proxmox against hosted: before the .NET jobs were merged 109 and 114 s against 74 and 79 s; after the merge and `Report` on hosted, median 66 s (63 to 72, five runs) against 58 s (48 to 76, five runs). A job on the runner spends about 14 s on GitHub round trips against about 3 s hosted (set-up 4 to 5 s against 1 to 2 s, an artifact upload 4 s against 1 s, about 9 s after the last step against 2 s), while compile (7 s against 6 to 11 s) and affected tests (13 s against 14 to 16 s) take about the same time; the earlier "tests twice as fast" was the hosted test job rebuilding on a fresh machine | `CONFIRMED` | docs/evidence/closeout/ci-runner-bench.txt; ci-runner-converge.txt, ci-runner-handler-drift.txt; ci-runner-guest-plan.txt, ci-runner-guest-plan-c52xl.txt |

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
- **Status:** DONE WHEN met on 2026-10-07 (independent audit PASS): two versions per class with hash-checked manifests, one-command rollback on both classes, a timer-fired rebuild, R15 baseline on clones (rows 55–60). Blast radius and actuals in 7.2a. Owner merges remain (PRs #76–#85).

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
- **Status:** DONE WHEN met on 2026-10-07 (independent audit PASS after two re-gates): hit ratio 38/38 dependencies and 57/57 restores over 19 runs by two instruments (row 63); the stale-binary test red on a stale variant and green on the new design in hosted CI (row 64); bad and edge paths, reboots and R15 measured (rows 61–70). Blast radius and actuals in 7.2b. Scope note: the repository had no NuGet or npm lockfile, so lockfiles were added (R8 keys the cache on lockfile hashes). The release ends after this phase (owner, change log); Phases 5–8 are handed off.

### Phase 5 — Runner pool controller

- **Do:**
  - JIT ephemeral runner per job.
  - Queue-driven scaling within host ceilings.
  - Warm pool and scale-to-zero.
  - Priorities, cancellation of superseded runs, and overflow to hosted per Q2.
  - Role-separated tokens.
  - Entry gate before the first runner registration: fork PRs routed to hosted in the workflows (row 27, D17; a 2026-10-07 review re-confirmed the current expression selects self-hosted for fork PRs) and the fork-approval setting on.
  - Entry gates from the Phase 3 review: runner clones do not keep the default user's NOPASSWD sudo that cloud-init restores at first boot (row 59), checked by an R15 row; root touches probe guests only after checking tag and pool, and runner VMIDs stay outside the template blocks; a per-runner firewall read-back (clones inherit the template firewall, row 58); an alert on stale templates or failed builds and a path to bump the runner pin.
  - Entry gates from the Phase 4 review: the cache writer credential is held only by save steps that run the cache client on artifacts the same run built (no third-party code in a writer job, checked by a canary); the `cache-writer` environment has a branch policy (owner) and the writer password is rotated after it is set; the controller's identity holds no privilege on the cache container's pool or the cache vnet; runners are JIT and ephemeral before they take any pull-request job; an alarm on cache writes outside writer jobs; a thin-pool headroom guard for runner disks and the cache volume; R15 re-run from a real JIT runner including the cache-vnet negatives; a host converge that would reboot drains the pool first.
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

> 88 rows: 84 decided, 1 superseded (D13 by D19), 3 open: D10 (controller) and D11 (language) for design, D60 for the owner. D1 and D2 were reworded on 2026-10-06 to remove organization references (R16); their substance is unchanged.

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
| D41 | Phase 2 OpenTofu state backend | MinIO S3 (`iac/tofu/backend.tf:9`, retired host) / local backend with state encryption | local backend in WSL with OpenTofu state encryption enforced (passphrase in SOPS); the local backend locks the state file; move to the Phase 4 S3 backend with `use_lockfile` | operator: the MinIO endpoint belongs to the retired host and the cache service arrives in Phase 4 | `DECIDED (2026-10-06)`; the move to S3 dropped by D79 | — |
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
| D60 | TOTP for `root@pam` and notifications (plan D59) | TOTP now / TOTP before regular remote use | TOTP is an owner step in the web UI (enrolment shows the secret to a human, about 2 minutes); the notification target waits for Phase 7 | owner: enrolment cannot be delegated | `SUPERSEDED (2026-10-08) by D90` for TOTP; the notification target stays open (Phase 7) | — |
| D61 | Requirements publication (plan D60) | publish this document as is / publish a redacted copy | `docs/platform/requirements.md` is built from this document by a sanitizing builder: the row-22 prefixes, the row-23 addresses, the workstation and user names become labels; local paths are removed; the unredacted copy stays operator-local; the repository copy is canonical once merged | operator: R16 and a public repository | `DECIDED (2026-10-07)` | 0034 |
| D62 | Hyper-V socket transport inside the PVE guest (new) | leave `hv_sock` loaded / block the module in the guest / also remove the integration devices on the Hyper-V side | block the module (`install hv_sock /bin/false`), unload it; integration devices stay | operator: it is a host↔guest channel outside every network control (R15); KVP/VSS are unused (ADR 0019) | `DECIDED (2026-10-07)` | 0028 |
| D63 | Owner of the storage definitions in Phase 2 (new; narrows the Phase 2 line "OpenTofu for storage") | OpenTofu manages storage / storage stays as the installer made it | storage stays as the installer made it: `local` (iso, vztmpl, backup, import) and `local-lvm` (guest disks) serve every Phase 2 need; OpenTofu reads them; Phase 3 (images) and Phase 4 (cache) name an owner | operator: changing storage definitions needs `Datastore.Allocate` on `/storage`, which also deletes any volume; the token's least privilege (D48) excludes it | `DECIDED (2026-10-07)` | 0035 |
| D64 | Who may change a golden template (Phase 3, security review) | templates in the guest pool with `VM.Clone` added to the guest role / a separate consumer token / a dedicated `templates` pool with a clone-only role | pool `templates`; role `HomelabTemplateClone` = {`VM.Clone`, `VM.Audit`} granted there to the provisioner user and token; `VM.Clone` in no other role; asserted by the role and a CI test | operator: in the guest pool the token could delete or retag templates (`VM.Allocate`, `VM.Config.Options`); a second token adds a secret without shrinking a token that already creates and destroys guests | `DECIDED (2026-10-07)` | 0036 |
| D65 | Guest firewall guard and extra rules (Phase 3, security review; strengthens D53/D55) | keep checking only that the group rule exists / reject any enabled rule outside the allowed set | a guest on the guest vnet violates when any enabled rule exists besides the `guest-egress` group and an inbound tcp/22 from the vnet gateway; guests off the vnet unchanged until Phase 4 | operator: a permissive rule beside the group rule survived the old guard, which ADR 0026 relies on to detect drift | `DECIDED (2026-10-07)` | 0037 |
| D66 | Where and how golden templates are built (Phase 3, amends ADR 0012's templates cell) | Packer / OpenTofu + provider + Ansible / a host-side orchestrator | root orchestrator on the host for `qm`/`pct` with host-chosen arguments, a non-root sandboxed guest-facing step, Ansible run inside the build guest; OpenTofu only consumes templates | operator: retention needs the root path anyway, no LXC builder in Packer, and the host never parses guest output | `DECIDED (2026-10-07)` | 0038 |
| D67 | Template model and retention | archive per version / Proxmox templates with linked clones | Proxmox templates on `local-lvm`, linked clones; keep `current` and `previous`; delete older only after the orchestrator's own clone-origin check | operator: LVM-thin does not refuse deleting a referenced base, measured in the storage code | `DECIDED (2026-10-07)` | 0039 |
| D68 | Versions, pointer and promotion | reviewed promotion in the repository / automatic promotion by tag | monotonic version, VMID block per class, a `current` tag moved only by root, automatic promotion after verification; a consumer pin overrides the tag | owner (2026-10-07): automatic | `DECIDED (2026-10-07)` | 0040 |
| D69 | Toolchain content of the runner templates | install per job / bake pinned toolchains | .NET SDK 8 and 10, Node 22 and the runner from release tarballs with pinned hashes; the runner installed, never configured; a non-root runner user without sudo | operator: the repository's self-hosted jobs skip `setup-dotnet` and `setup-node` | `DECIDED (2026-10-07)` | 0042 |
| D70 | Container engine in the VM class | upstream engine repository / the distribution package | Debian's `docker.io`, unix socket only | operator: no third-party key, distribution security cadence | `DECIDED (2026-10-07)` | 0043 |
| D71 | How consumers select a template, and the R15 probe | name a VMID / resolve fail closed | resolve among pool `templates` members by marker, class and `current` (or a pinned version): exactly one, a template, VMID in the class block; the R15 probe clones from the templates | operator: clones inherit tags, so the pool is the boundary | `DECIDED (2026-10-07)` | 0044 |
| D72 | Owner of base images, snippets content and the rebuild schedule (refines D63) | the API token / Ansible as root | the template role fetches base images with pinned sha512, adds `snippets` to storage `local`, runs a weekly rebuild with catch-up, and never starts the VM itself (D25 unchanged) | operator: deleting volumes needs `Datastore.Allocate`, which no token holds | `DECIDED (2026-10-07)` | 0041 |
| D73 | Cache placement (Phase 4) | a peer on the guest vnet / a service on the hypervisor / a container on its own routed vnet | container `cache01` on vnet `cache` (10.99.17.0/24) in zone `hlab`, routed through pve01 | operator: the guest vnet isolates ports (row 51), and the hypervisor must not serve untrusted runners | `DECIDED (2026-10-07)` | 0045 |
| D74 | Runner-to-cache path | per-guest rules / one group-level rule | the first line of `guest-egress` accepts tcp to the cache address and port; new group `cache-ingress` on the container; endpoint from the inventory | operator: per-guest rules would break the guard's runner allowed set (ADR 0037) | `DECIDED (2026-10-07)` | 0046 |
| D75 | Guard rule for guests outside the guest vnet (open since Phase 3) | ignore them / per-vnet policy | a policy file maps each vnet to its required groups and optional gateway ssh rule; a guest with a NIC on any other bridge is a violation | operator: a guest on the management bridge would bypass every vnet control | `DECIDED (2026-10-07)` | 0047 |
| D76 | Cache store | MinIO community / Garage / SeaweedFS / nginx WebDAV + janitor / bazel-remote | bazel-remote 2.6.2, pinned by sha256, uncompressed storage | operator: MinIO community is archived and source-only; only bazel-remote verifies CAS digests on upload, splits anonymous reads from authenticated writes and evicts by size, in its own code (read at the release tag) | `DECIDED (2026-10-07)` | 0048 |
| D77 | Keys and stale binaries | latest archive + timestamp bumps / content keys with exact-match outputs | dependency caches keyed by lockfiles, toolchain, OS, arch and runner class; outputs by the input tree ids, configuration and workspace root, restored only on an exact match | operator: rows 18 and 64; R8 | `DECIDED (2026-10-07)` | 0049 |
| D78 | Write boundary | reader and writer keys / anonymous reads + one writer credential | anonymous reads; one writer credential only in environment `cache-writer`; its branch policy is an owner setting | operator: cache content is public-repository build output reachable only from the runner vnet | `DECIDED (2026-10-07)` | 0050 |
| D79 | OpenTofu state after Phase 4 (narrows D41) | move to the cache / stay local and encrypted | stays local and encrypted; D41's planned move to "the Phase 4 S3 backend" is dropped | operator: the cache is reachable by untrusted runners and is not an S3 store | `DECIDED (2026-10-07)` | 0051 |
| D80 | Proof runner before Phase 5 | wait for the controller / a linked clone of the runner template driven from pve01 | the R15 probe clones (ADR 0044) stand in for runners; hosted CI carries the stale-binary test | operator: same template and firewall policy as a real runner | `DECIDED (2026-10-07)` | 0053 |
| D81 | Results in the repository (R20) | keep evidence outside / publish raw / regex masking / exact-value map + checker | sanitized copies by exact-value substitution from an operator-local map; a checker that flags and never rewrites; hash-anchored files byte-identical or withheld; the deny list stays outside the repository | owner (R20); a pattern mask once rewrote a package version | `DECIDED (2026-10-07)` | 0052 |
| D82 | CI routing until the runner pool exists (release close) | keep the self-hosted default / deregister the old runners / hosted by default until Phase 5 | the caller workflow runs the reusable pipeline on hosted runners by default; the self-hosted path and cache wiring stay; Phase 6 flips it back | operator: own-repository runs queue 24 h on two offline runners of the retired host; the hosted path is green with the new wiring (row 68) | `DECIDED (2026-10-07)` | 0054 |
| D83 | Creating a guest sized by a cloud flavor (release close-out) | Proxmox UI only (it has no instance-type field) / hand off to the Phase 5 controller / a guest stack plus one command now | a guest stack that reads `flavors.json` plus `scripts/iac/new-guest.sh`; guests are tagged with their flavor so the UI shows it | owner: "build it now"; operator: the catalog and its test existed but no stack used them (`module flavor` only in `flavor.tftest.hcl`) | `DECIDED (2026-10-07)` | 0055 |
| D84 | Tests the release audit found missing | record as named gaps / write them now | Pester tests for `HomelabHyperV.psm1`, render and mutation tests for roles `pve_host` and `hyperv_guest`, and published line-coverage numbers | owner: write the tests now (not named gaps), plus "show the coverage numbers" | `DECIDED (2026-10-07)` | 0057 |
| D85 | General object storage (artifacts, backups, state) | build now / hand off / none | handed off to Phase 7 with backups; candidate Garage (S3-compatible, maintained; ADR 0048 rejected it only as a cache for lacking LRU) | owner: hand off | `DECIDED (2026-10-07)` | none (handoff item) |
| D86 | Lab machines after the release | stop pve01 per D21 / keep everything running | keep pve01, `cache01`, the templates and the probes running as evidence that the platform works; D21's on-demand stop is suspended until the owner says otherwise | owner: "do not shut anything down or delete any machine yet" | `DECIDED (2026-10-07)` | none |
| D87 | The affected-test selector had a Bash and an unreferenced PowerShell implementation | keep both with a parity test / keep one | keep the Bash selector only; delete the PowerShell copy and its harness | operator: no action or workflow ran the PowerShell copy; code review (release close-out) | `DECIDED (2026-10-07)` | 0056 |
| D88 | Coverage tools and gates | none / coverage.py, Pester and kcov with floors | coverage.py for the Python suites and Pester's built-in coverage, each in CI; a floor at the lowest recorded total (hosted CI and local runs) rounded down, as a regression guard; kcov only locally because `ubuntu-latest` (24.04) has no kcov package | owner: "show the coverage numbers" (D84) | `DECIDED (2026-10-07)` | 0057 |
| D89 | Owner-only security steps after the release | wait for the owner / the operator runs them on the owner's go | the operator deregistered the retired runners, set fork approval to all external contributors, limited `cache-writer` to `master` and rotated the writer password, and removed the stale wiki pages; TOTP on `root@pam` stays with the owner (the second factor lives on the owner's device) | owner (translated): "you do 1, 2, 3 and 5; let's talk about 4" | `DECIDED (2026-10-08)` | none |
| D90 | Proxmox login-layer hardening (TOTP on `root@pam`, D60) | enrol TOTP now / keep it off in the lab and document it for adopters | keep it off in the reference lab; ADR 0058 records what still protects the web UI, the risk accepted, and when and how an adopter turns it on (the TFA button in the user list, recovery keys) | owner (translated): "this is a proof of concept, a learning project and a base others will adapt; do not make it harder to use, document what to do and why" | `DECIDED (2026-10-08)` | 0058 |
| D91 | Open the lab to visitors | keep fork approval and a generated root password / loosest fork approval, a shared demo root password, owner-approved merges / the same with a separate limited Proxmox user | fork approval `first_time_contributors_new_to_github` (no API value turns it off); `root@pam` gets a shared demo password kept in SOPS, not written in the repository; `master` keeps the code-owner review; the limited-user option was offered and declined | owner (translated): "let everyone use it"; "set the root password to a simple value so others can come in and try the proof of concept"; "pull requests need my approval only" | `DECIDED (2026-10-08)` | 0059 |
| D92 | Lab accounts | a shared root password only / root plus a read-only visitor on every machine | every machine has `root` and a visitor with the same passwords everywhere: `root@pam` and `guest@pve` (role `LabGuest`: `PVEAuditor` privileges plus `VM.Console`) on the web UI, local `root` and `guest` (no administrative group) in each guest; values in SOPS only; applied by `lab-accounts.yml`, guest-stack VMs at every boot through a vendor snippet | owner (translated): "every machine has two accounts, root and guest, the same on every machine; guest sees everything but read-only" | `DECIDED (2026-10-08)` | 0059 |
| D93 | CI on a Proxmox runner | wait for the Phase 5 JIT pool / one persistent runner container behind a job-start guard, routed by a repository variable / ephemeral runners re-registered by a script after each job | one unprivileged container (`aws/c5.2xlarge`, VMID 9503) with three runner instances; the job-started hook refuses every event except push, dispatch, schedule and a pull request from a branch of this repository; `vars.CI_RUNNER=proxmox` routes `sdet-ci.yml`, fork pull requests always hosted; each instance restarts after its job (actions/runner#4444); .NET build and test in one job and `Report` on `ubuntu-latest`, on both paths | owner (translated): "move as much as possible to run on Proxmox; add an LXC so GitHub Actions uses a Proxmox runner"; "forks stay open, but only GitHub Actions may use my machine; use a GitHub variable"; "how do we make it faster than GitHub-hosted" | `DECIDED (2026-10-08)` | 0060 |

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

### 7.2a Blast radius estimate — Phase 3 (recorded 2026-10-07, before starting)

| Dimension | Estimate at opening | Actual at closing |
|---|---|---|
| What breaks, how many | pve01 storage: a full thin pool (62.5 GiB) stops every guest write on 1 host; one build guest at a time inside the 20 GiB VM; 0 runners exist yet (Phase 5), so 0 CI jobs; 0 laptop components (the VM is capped by D19) | nothing broke outside the build guests: failed builds destroyed their own guests (two were stopped by hand before that fix); thin pool at 20.06% with four retained templates; 0 CI jobs; the laptop ran on battery for part of the run |
| Furthest environment | `none (CI / local only)`: laptop, pve01, PR CI | as estimated |
| Time to detect | immediately for a failed build (exit code); a slow disk fill is found late, so a pre-build free-space check that refuses the build is added before the first build | immediately: each defect stopped its build or converge at the failing step, with the cause in the journal |
| Time to roll back, and who | template: one rollback command, seconds, operator; host: stopped-VM checkpoint restore + start about 16 s, operator, no approval | one rollback command measured (exit 0, seconds); no host restore was needed |

### 7.2b Blast radius estimate — Phase 4 (recorded 2026-10-07, before starting)

| Dimension | Estimate at opening | Actual at closing |
|---|---|---|
| What breaks, how many | pve01 thin pool: one cache volume of at most 10 GiB, thin (pool 62.5 GiB, about 20% used); R15: one new allowed runner path (tcp to one cache address and port), and a wrong rule could open more, caught by the R15 probe before any runner exists (0 runners registered); repo CI: the cache steps of the reusable pipeline on PR branches only (self-hosted jobs queue on the offline old runners; the hosted path runs on dispatch), so 0 effect on master  | thin pool 24.29% after the phase (one 4 GiB root + one 10 GiB data volume, thin); R15 held: 19/19 negatives from runners and 12/12 from the cache container, before and after a pve01 reboot, with red-first controls; 0 CI jobs broken (self-hosted jobs still queue; the hosted fallback runs green with the cache disabled, run 37602620111); one cache outage of our own making (a start-time address check that could not run in the unit's sandbox), found on a container reboot and fixed the same hour |
| Furthest environment | `none (CI / local only)`: laptop, pve01, hosted PR CI  | as estimated |
| Time to detect | build and test failures immediately (exit code); an R15 regression at the host-run probe (minutes); cache disk growth through a size and eviction metric exposed in this phase (alerting is Phase 7)  | immediately for every defect found: each showed in the run that hit it (guard violation within its 1-minute timer, `status=rejected`/`refused`/`failed` lines, a failed unit start in the journal); the phase-end review and audit found the design gaps |
| Time to roll back, and who | `tofu destroy` of the cache stack and a converge without the group rule, minutes, operator, no approval; PR branches revert by commit  | no rollback needed; the service outage was fixed forward in minutes by the operator; a cache purge or a container rebuild costs only a cold cache |

### 7.2c Blast radius estimate — Proxmox runner, D93 (recorded 2026-10-08, before starting)

| Dimension | Estimate at opening | Actual at closing |
|---|---|---|
| What breaks, how many | when the runner is offline, every routed SDET run queues for up to 24 hours (six jobs per run); other workflows stay hosted; `pve01` gives the container 4 of 12 cores and 8 of 20 GiB, later 8 cores and 16 GiB | 0 runs broken on `master` (routing takes effect at merge); on the branch, a listener stall after each job (actions/runner#4444, 225 s runs) and an orphan listener left by `KillMode=process` (a 64 s queue) were found and fixed before measurement |
| Furthest environment | the repository's CI and `pve01` | as estimated |
| Time to detect | the first queued job, within minutes of a push | each defect showed in the run that hit it, as queue time in the job timeline |
| Time to roll back, and who | under one minute: `gh variable set CI_RUNNER --body hosted`, by the owner | not needed |

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
| T | **Test first** — every new piece must be shown able to fail:<br>• controller unit tests written red first<br>• mutation tests of the queue, scaling and cache-key logic<br>• the stale-binary test, red on current code before the fix<br>• IaC checked by `tofu test` and Molecule | `controller/` tests, `standard/tests/`, run URLs | `partly met`: the stale-binary test red first (row 64), mutation tests of the cache keys, extraction, workflow secrets and every isolation control (rows 64, 70; `docs/knowledge/test-catalogue.md`), IaC checked by `tofu test` and Molecule; controller tests are Phase 5 (handed off) |
| P | **Performance** — full-suite wall-clock and queue-to-start | Baselines: run [37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969) (hosted, 71 s) and run [37341728563](https://github.com/ugritchaichana/booth-homelab/actions/runs/37341728563) attempt 2 (self-hosted, 174 s), vs runs after cutover | `not measured`: Phase 6 (handed off); the hosted fallback runs green with the new wiring (row 68) |
| 1 | R1: PVE 9 here within budget; daily work unbroken | `pveversion`, `Get-VM`, `Get-Volume`, `wsl -l -v` | `done` (rows 35, 36, 40, 53) |
| 2 | R2: timed rebuild from zero via the runbook is green | criterion 3.4 evidence | `not done`: Phase 8 (handed off) |
| 3 | R3: flavor catalog test passes; plan sizes correctly | test + `tofu plan` | `done`: catalog test (row 60, IaC CI run 37560039041) and the guest stack sizes clones from it on pve01 (row 71) |
| 4 | R4: plan 0; second Ansible run `changed=0`; IaC CI meets criterion 2.5 | run URLs | `done` (rows 46, 49, 54, 61) |
| 5 | R5: N-host inventory, scoped ACLs, two template versions, clones removed after jobs | `pveum acl list`, logs | `partly met`: N-host inventory (row 60, two-host plan test), scoped ACLs (rows 48, 57), two template versions (row 56); clones removed after jobs is Phase 5 (handed off) |
| 6 | R6: every unit is `workflow_call`; callers only `uses:` | actionlint + checker script | `not done`: Phase 6 (handed off) |
| 7 | R7 + R8: Q7 targets, load test, priority / cancellation, hit ratio | controller logs + run URLs | `partly met`: cache hit ratio (row 63); load test, priority and cancellation are Phases 5–6 (handed off) |
| 8 | R9: dependency rule enforced and failing on violation | lint / test | `met for the cache client` (dependency-rule test with mutations, row 64); the controller is Phase 5 (handed off) |
| 9 | R10: portability proof on a non-Proxmox host | run URL | `not done`: Phase 8 (handed off) |
| 10 | R11: every master commit came through a PR | `gh pr list --state merged` vs `git rev-list` | `done` for the release: all PRs merged by the owner with merge commits; on master `86324ee` the 46 first-parent merges are all "Merge pull request" and the 59 direct commits predate R11 (2026-10-05 or earlier); release audit 2026-10-07 |
| 11 | R13: gitleaks 0; 0 by-value matches against old values | CI output + scan script | `done` for this release: gitleaks and the neutrality scan before every push, by-value scans of published evidence (row 69) |
| 12 | R15: every negative test fails, before and after reboots | output from inside runners, stored as criteria 1.3 / 1.5 evidence | `done` (rows 52, 59, 66) |
| 13 | R16: deny-list grep = 0 over repo, open PR branches and PR bodies; no non-English text in repo docs | grep output | `done` on master `86324ee`: previous-agent product names 0 and Thai characters 0 over the tracked tree (`git grep` and a second Python scan of 486 files, release audit 2026-10-07); two commit subjects in history (`62c463e`, `44a7725`) keep a hardware model and an old agent abbreviation, rewriting history is owner-only |

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
| 2026-10-07 | Phase 3 started on the owner's go (translated: "merged, start Phase 3", about 08:20 ICT; D32 had covered Phases 1–2 only). Blast radius recorded in 7.2a before any job. The Phase 2 chain #57–#75 was not merged at that time: master needs one approving code-owner review and the author cannot approve their own PR, so the owner merges with the admin bypass | Owner go for Phase 3 |
| 2026-10-07 | Added R18: the owner does not operate the platform; the work is implemented, tested and measured here and handed over with docs and a runbook to another team's technical lead | Owner statement |
| 2026-10-07 | Phase 3 DONE WHEN met: rows 55–60, decisions D64–D72 with ADRs 0036–0044, 7.2a actuals. Run in a temporary fast mode the owner asked for (parallel small jobs; one security review and one audit at phase end). The host runs found seven defects that offline tests could not, each fixed in a PR. Phase 5 entry gates added from the phase-end security review: cloud-init must not restore the default user's sudo on runner clones; root acts on probe guests only after checking their tag and pool, and runner VMIDs stay outside the template blocks; a per-runner firewall read-back; a signal for stale templates and failed builds, plus a way to bump the runner pin | Independent audit PASS after two re-gates |
| 2026-10-07 | Owner go for Phases 4–8 (translated: "continue after the compaction until it is finished as designed"): phase after phase without a new go per phase; work stops only at owner-only steps (merges, GitHub settings, fine-grained tokens, deregistering the old runners, a backup device, a portability host, UAC and reboots), a red DoD, or a design-changing decision | Owner statement |
| 2026-10-07 | Added R19, the release definition of done: complete system with happy/bad/edge tests for every component, all on this laptop; then merge (owner-authorized; the owner runs the prepared merge commands because the harness blocks merges by the operator), docs up to date, previous-agent debt cleared, handoff documents; fully autonomous run in fast mode | Owner statement |
| 2026-10-07 | Phase 4 started (owner go for Phases 4–8; R19). Blast radius in 7.2b before any job. Scope reopened in one place: lockfiles are added to `apps/` because the cache keys on them and none exist | Document first |
| 2026-10-07 | Added R20: the repository holds the results (sanitized evidence per phase), the knowledge and the code; Phases 1–3 backfilled | Owner statement |
| 2026-10-07 | Owner decision on the release scope (asked with measured options: Phase 4 took about 3.5 hours; Phases 5–8 not started, estimated 12–20 hours as a HYPOTHESIS): the release ends after Phase 4. R19 now reads: Phases 0–4 complete and tested on this laptop, then the merge, the documentation pass, the previous agent's debt and a handoff package that hands Phases 5–8 (controller, workflow cutover, observability and backups, rebuild-from-zero and portability) to the team that builds production, with the research, designs and entry gates already written | Owner answer |
| 2026-10-07 | Phase 4 DONE WHEN met: rows 61–70, decisions D73–D81 with ADRs 0045–0053, 7.2b actuals, Phase 5 entry gates from the phase-end review. Nine defects found only on the real host and fixed in PRs (container started before its firewall, server 500 on a digest mismatch, 64-hex names, wrong-password upload misread, partial blob served after a crash, first-start bind race, an address check blocked by the sandbox, stale probe host keys, a stale link-local target); the audit found a hosted-path expression defect (fixed) and record gaps (fixed) | Independent audit PASS after two re-gates |
| 2026-10-07 | Release close-out reopened scope after the owner's eight points and the failed release audit: flavor guests by one command (D83), the missing tests plus coverage (D84), object storage to Phase 7 (D85), machines kept running (D86), worked examples for adopters, README badges and the About text. Mission document in the operator notes | Owner statement |
| 2026-10-07 | Close-out results: rows 71-74 (flavor guests, renames, new tests, coverage), D87-D88, R3 to done; PRs #102-#110 plus the docs and examples PRs prepared for the owner's merge | Measured |
| 2026-10-07 | Release close-out audited: security review SHIP (four Phase 5 entry gates added); release re-audit RELEASE READY after two NOT READY rounds whose findings were fixed (tflint precondition, guest-list re-capture, coverage figures, diagram, actionlint in CI, an ansible-lint line length). PRs #102-#114 wait for the owner's merge script | Independent audit |
| 2026-10-07 | Release close-out merged: PRs #102-#114 merged by the owner's idempotent merge script (stacked PRs retargeted to master and refreshed before each merge); master `688d64f`; every remote branch except master deleted. Master CI green on `688d64f`: SDET pipeline 37654683496, Secret Scan 37654682812, Evidence Publisher Gate 37654682686 (coverage 94.75%, floor 94), Standard Scorecard 37654682759 (89.52%, floor 89), and dispatched on master: Cache client CI 37654825674 (89.38%, floor 86), Hyper-V host layer CI 37654830254 (Pester 99.26% pwsh, 99.01% Windows PowerShell), IaC Governance & Quality Gate 37654834701, Affected Test Selector CI 37654820689, Workflow Lint 37654838925. pve01 guests 9050, 9101, 9102, 9501, 9502 running; templates stopped by design (D86) | Measured |
| 2026-10-08 | Owner-authorized security steps run by the operator (D89, row 75): retired runners deregistered, fork approval for all external contributors, `cache-writer` limited to `master`, writer password rotated and converged, stale wiki pages removed; the handoff documents and blocking conditions updated in one PR. TOTP on `root@pam` stays an owner step | Owner statement |
| 2026-10-08 | D90: TOTP on `root@pam` stays off in the reference lab by the owner's decision (supersedes the TOTP part of D60); ADR 0058 and the adopter table in the security model say what to turn on, when and why | Owner statement |
| 2026-10-08 | D91: the lab is opened to visitors (ADR 0059): fork approval at the loosest value, a shared demo root password set on `pve01` and stored in SOPS (web UI login read back: correct value 200, wrong value 401; SSH still refuses passwords), merges still need the owner's code-owner review. Phase 5 entry gate 1 now also covers restoring fork approval or routing forks to hosted | Owner statement |
| 2026-10-08 | D92 and row 76: root and a read-only visitor account on every machine, the same passwords everywhere (values in SOPS only); ADR 0059 rewritten for the two-account model while still unmerged | Owner statement |
| 2026-10-08 | D93 and row 77: the repository's own SDET runs move to one persistent runner container on `pve01` behind a job-started hook, routed by `vars.CI_RUNNER` (ADR 0060, supersedes part of ADR 0054); the .NET jobs merged and `Report` moved to hosted after measurement; the Phase 5 JIT gate is recorded as not met by this runner | Owner statement + measured |

### Owner actions (besides merging)

| When | Action | Why |
|---|---|---|
| Done 2026-10-08 (D89) | Set fork PR approval to "all external contributors": Settings → Actions → General → "Fork pull request workflows from outside collaborators" | Closes the row-27 gap until cutover. Deferred by the owner on 2026-10-06: finish the neutral repo first |
| Before Phase 1 | Give the go for Phase 1 | R12 is met; work starts on the owner's go |
| Phase 1 | Accept the UAC prompt for the Hyper-V and VM scripts; reboot when convenient | The shell is not elevated (row 8) |
| Phase 2 | Keep a backup copy of the age key off this machine | D12: losing the machine would lock every secret. SUPERSEDED 2026-10-06: moved to Phase 1 (D23) |
| Phase 1 | Keep a backup copy of the age key off this machine, before the PVE install | D23: the root password is stored per Q6 from the first boot |
| Phase 5 | Create two fine-grained tokens scoped to `booth-homelab`:<br>• Administration read/write for the controller (JIT minting)<br>• Administration read for the router (pool availability) | D14, D15: token creation is an account setting |
| Done 2026-10-08 (D89) | Give an explicit go to deregister the old runners | Section 2.1 row 11 |
