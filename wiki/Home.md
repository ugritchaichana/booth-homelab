# Homelab CI Platform Knowledge Base

A learning homelab: Proxmox VE 9 runs as a Hyper-V VM on a Windows workstation, is rebuilt from code, and is meant to host single-use CI runners. The platform is built and measured through the build cache; the runner pool and everything after it are handed off. Per-phase status: [docs/handoff/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/README.md). CI runs on GitHub-hosted runners today ([ADR 0054](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md)).

The repository is the source of truth; these pages point into it.

## Pages

| Page | Content |
|---|---|
| [01 Architecture and Design](01-Architecture-and-Design) | Host, VM, networks, guests, isolation layers (summary page) |
| [02 Golden Templates](02-Golden-Templates) | Runner templates, versioning, rollback, consumption |
| [03 Build Cache](03-Build-Cache) | The `bazel-remote` cache service and its client |
| [04 Transitive Affected Testing](04-SDET-Transitive-Affected-Testing) | The .NET affected-test selector and the CI pipeline layout |
| [05 Measured Results](05-Measured-Results) | CI, cache, template, isolation and host results (summary page) |
| [06 Operational Runbooks and Troubleshooting](06-Operational-Runbooks-and-Troubleshooting) | Where each procedure and failure is handled (summary page) |
| [07 Infrastructure as Code](07-Infrastructure-as-Code-OpenTofu-Ansible) | Inventory, Ansible, OpenTofu and SOPS layout (summary page) |
| [08 Runtime Support and Upgrade Plan](08-Runtime-Support-and-Upgrade-Plan) | Pinned runtimes, support dates, upgrade order |

## Canonical homes

| Fact | Where |
|---|---|
| Architecture | [docs/handoff/architecture.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/architecture.md) |
| Measured results | [docs/handoff/results.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/results.md) |
| Operations | [RUNBOOK.md](https://github.com/ugritchaichana/booth-homelab/blob/master/RUNBOOK.md) |
| IaC layout | [iac/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/iac/README.md) |
| Phase status | [docs/handoff/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/README.md) |
| Test and coverage numbers | [docs/knowledge/coverage.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/knowledge/coverage.md), [docs/knowledge/test-catalogue.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/knowledge/test-catalogue.md) |
| Why a choice was made | [docs/adr/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/README.md) |
| Defects the real host exposed | [docs/knowledge/real-host-defects.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/knowledge/real-host-defects.md) |
| Rules for contributors | [AGENTS.md](https://github.com/ugritchaichana/booth-homelab/blob/master/AGENTS.md) |
