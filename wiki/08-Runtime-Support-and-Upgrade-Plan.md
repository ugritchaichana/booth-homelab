# 08. Runtime Support and Upgrade Plan

Purpose: record every pinned runtime that is past, or within 30 days of, its vendor's end of security support, with a dated upgrade plan. The standard treats "a component within 30 days of its end date with no dated upgrade plan in the repo" as unsupported, and check 2.7 compares the repo's pins with `endoflife.date`. Dates below are proposed by the owner; merging this page accepts them.

Pin locations are given at commit `8cc8abc` (the base of the PR that introduced this page). End-of-support dates were read from endoflife.date on 2026-10-05.

## Component plan

| Component | Pinned version and where | Vendor end of security support | Status on 2026-10-05 | Target | Dated milestones | Who |
|---|---|---|---|---|---|---|
| Proxmox VE | 8.4 (`AGENTS.md:12`); `iac/bootstrap/bootstrap.sh:19` targets PVE 8.x | 2026-08-31 | Overdue: past end of security support. This plan records the date; it does not lift the condition. | 9 | Host upgrade complete by 2026-10-31 | owner |
| Node.js | 20 before this PR; 22 after (`.github/workflows/reusable-sdet-pipeline.yml:220,224`, `iac/ansible/roles/runner_angular/tasks/main.yml:6-8`, `scripts/proxmox/provision-angular-runner.py:120`, `apps/frontend/package.json:23`) | 2027-04-30 (Node 22) | Node 20 ended 2026-04-30; repo pins move to 22 in this PR. CT 103 still runs Node 20 until re-provisioned. | 22 now; 24 with the Angular upgrade | CT 103 re-provisioned with Node 22 by 2026-10-31. Node 24 together with an Angular 20 or newer upgrade, done by 2027-03-31 (30 days before Node 22 ends) | owner (CT 103), agent (repo pins) |
| .NET | 8 (see checklist below) | 2026-11-10 (.NET 8) | Within 30 days of end on 2026-10-11; unsupported from that date without this plan | 10 (supported to 2028-11-14) | SDK 10 on the runner image by 2026-10-24. Retarget plus test packages by 2026-10-31. All green and hosted fallback on `10.0.x` by 2026-11-07 | agent (code, workflows), owner (runner image) |
| Alpine (MinIO CT 104) | 3.23 (`iac/ansible/roles/proxmox_host/tasks/main.yml:16-17`, `iac/tofu/variables.tf:113`, `iac/tofu/terraform.tfvars.example:25`). `scripts/proxmox/auto-configure-pve.py:6,55,68` still references 3.20: reconcile with 3.23. | 2027-11-01 | Supported | Review for a newer release | Review by 2027-10-01 | owner |
| Debian (runner CT templates) | 12 (`iac/ansible/roles/proxmox_host/tasks/main.yml:10-11`) | 2028-06-30 (LTS) | Supported | Debian 13, with the Proxmox 9 templates | Review by 2028-05-31 | owner |

## .NET 8 to 10 checklist

Pins to change, all at `8cc8abc`:

- [ ] `apps/backend/src/Billing.Api/Billing.Api.csproj:4` `net8.0`
- [ ] `apps/backend/src/Core.Application/Core.Application.csproj:8` `net8.0`
- [ ] `apps/backend/src/Core.Domain/Core.Domain.csproj:4` `net8.0`
- [ ] `apps/backend/src/Order.Api/Order.Api.csproj:8` `net8.0`
- [ ] `apps/backend/tests/Billing.Api.UnitTests/Billing.Api.UnitTests.csproj:4` `net8.0`
- [ ] `apps/backend/tests/Order.Api.IntegrationTests/Order.Api.IntegrationTests.csproj:4` `net8.0`
- [ ] `apps/backend/tests/Order.Api.UnitTests/Order.Api.UnitTests.csproj:4` `net8.0`
- [ ] `.github/workflows/reusable-sdet-pipeline.yml:106` and `:157` `dotnet-version: '8.0.x'` to `'10.0.x'`
- [ ] `.github/workflows/affected-selector-ci.yml:34` `dotnet-version: '8.0.x'` to `'10.0.x'`
- [ ] `iac/ansible/roles/runner_dotnet/tasks/main.yml:17-19` `dotnet-sdk-8.0` to `dotnet-sdk-10.0` (confirm the package exists in the Microsoft apt feed for the runner's Debian release first)
- [ ] `scripts/proxmox/provision-runner.py:121` `--channel 8.0` to `--channel 10.0`
- [ ] Doc mentions of .NET 8: `README.md:9` badge, `wiki/07-Infrastructure-as-Code-OpenTofu-Ansible.md:11`

Test-package compatibility, in each of the three test csproj files (`PackageReference` lines 13-16):

- [ ] `Microsoft.NET.Test.Sdk` 17.8.0 predates .NET 10: bump during the retarget
- [ ] `xunit` 2.5.3 and `xunit.runner.visualstudio` 2.5.3: check against the .NET 10 SDK and bump if the test host fails to discover tests
- [ ] `coverlet.collector` 6.0.0: check coverage collection runs on .NET 10 and bump if it does not

Order: runner image first (SDK 10 installed next to SDK 8), then retarget and package bumps in one change, then the workflow pins, then remove SDK 8.

## Update after re-provisioning

These lines record what was measured on the live host and stay at Node 20 until CT 103 is re-provisioned with Node 22. Update them with the measured versions afterwards.

- `AGENTS.md:15`
- `AI_CONTEXT.md:45`
- `RUNBOOK.md:221`
- `wiki/05-Performance-Benchmark-Results.md:49`

Re-provisioning note: `iac/ansible/roles/runner_angular/tasks/main.yml` skips the NodeSource setup when `/etc/apt/sources.list.d/nodesource.list` exists, so an existing CT 103 keeps the Node 20 repository. `provision-angular-runner.py` skips the whole Node block when `node` is already on PATH. For either tool, re-provision CT 103 from a clean template.

## How to re-check

```
curl -s https://endoflife.date/api/proxmox-ve.json
curl -s https://endoflife.date/api/nodejs.json
curl -s https://endoflife.date/api/dotnet.json
curl -s https://endoflife.date/api/alpine-linux.json
```

Compare the `eol` field of each cycle with the pins in the table above, and update the table when a pin or date changes.
