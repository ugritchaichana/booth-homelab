# Homelab CI Platform Knowledge Base

A neutral homelab baseline: Proxmox VE 9 runs as a Hyper-V VM on a Windows workstation, is rebuilt entirely from code, and is meant to host single-use CI runners. These pages summarize the platform. The repository is the source of truth; each page names the files and decisions it summarizes.

## Status

| Phase | Scope | State |
|---|---|---|
| 0 to 4 | Requirements, Hyper-V VM and isolation, IaC foundation, golden templates, build cache | Built and measured |
| 5 | Runner pool controller | Not built, handed off |
| 6 | Workflow cutover to the new runners | Not built, handed off |
| 7 | Observability and backups | Not built, handed off |
| 8 | Rebuild-from-zero and portability proof | Not built, handed off |

CI runs on GitHub-hosted runners today (ADR 0054, `docs/adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md`). The self-hosted path is wired and proven on the host but has no online runners until Phase 5; the retired host's runners are offline until Phase 6 deregisters them. The hand-off package is `docs/handoff/README.md` in the repository.

## Pages

| Page | Content |
|---|---|
| [01 Architecture and Design](01-Architecture-and-Design) | Host, VM, networks, guests, the two isolation layers |
| [02 Golden Templates](02-Golden-Templates) | Runner templates, versioning, rollback, consumption |
| [03 Build Cache](03-Build-Cache) | The `bazel-remote` cache service and its client |
| [04 Transitive Affected Testing](04-SDET-Transitive-Affected-Testing) | The .NET affected-test selector and the CI pipeline layout |
| [05 Measured Results](05-Measured-Results) | Every number that a run or a requirements row backs |
| [06 Operational Runbooks and Troubleshooting](06-Operational-Runbooks-and-Troubleshooting) | Where each procedure lives and the defects found on the real host |
| [07 Infrastructure as Code](07-Infrastructure-as-Code-OpenTofu-Ansible) | OpenTofu, Ansible, SOPS layout |
| [08 Runtime Support and Upgrade Plan](08-Runtime-Support-and-Upgrade-Plan) | Pinned runtimes, support dates, upgrade order |

## Where the detail lives

| Need | Repository path |
|---|---|
| Requirements, measured rows, decision log | `docs/platform/requirements.md` |
| Why a choice was made | `docs/adr/` (index in `docs/adr/README.md`) |
| What a run proved | `docs/evidence/<phase>/INDEX.md` |
| Defects the real host exposed, test catalogue | `docs/knowledge/` |
| Procedures | `RUNBOOK.md` |
| Rules for contributors and agents | `AGENTS.md` |
