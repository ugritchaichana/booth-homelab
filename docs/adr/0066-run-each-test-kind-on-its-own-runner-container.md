# 0066. Run each test kind on its own runner container

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner
- Decision log: D100 in docs/platform/requirements.md
- Amends: 0060 (one container, three instances), 0064 (job placement)

## Context

The Phase 5 load test (ADR 0065) sends two repositories' runs to the Proxmox runner: an Angular repository (Jest) and a .NET repository (unit and integration tests). Three instances in one container took any job. GitHub hands out queued jobs in creation order. Angular jobs exist from the dispatch, while the .NET suites appear only after the build. The three slots therefore filled with whichever kind came first. In five rounds, all three kinds ran at once at one job start.

## Options considered

1. **Keep three instances that take any job** (ADR 0060, 0064). The kinds compete in creation order.
2. **Label the three instances by kind, in the same container.** The kinds stop competing for slots, but they still share one container's CPU, memory, disk and restarts.
3. **One container per test kind, with one runner each.** Each kind gets its own queue and its own resources.

## Decision

Option 3, decided by the owner.

| Runner (container) | Flavor | Jobs |
|---|---|---|
| `dotnet-unit-auto` (`dotnet-unit-auto-lxc-runner-v7`, VMID 9504) | `aws/c5.xlarge`, 50 GiB | Build (.NET), Test (.NET unit), the .NET cache save. The build runs here only. |
| `dotnet-integration-auto` (`dotnet-integration-auto-lxc-runner-v7`, VMID 9505) | `aws/c5.large`, 30 GiB | Test (.NET integration) |
| `workspace-unit-auto` (`workspace-unit-auto-lxc-runner-v7`, VMID 9506) | `aws/c5.large`, 30 GiB | Test (Angular), the Angular cache save |

- **Registration.** `iac/ansible/playbooks/ci-runner.yml` converges one instance (`actions-runner@1`) per role container. A container is found by the prefix `<role>-lxc-runner-v`. The runner is named `<host>-<role>` and labelled `proxmox,<role>`. The unit keeps the shared path (`BindPaths`), the private `/tmp` and the job-start guard (ADR 0064). A changed script or unit restarts a running instance with `systemctl try-restart`.
- **Routing.** `Select Runner` passes the run's suites to `runner_route.py decide`. Proxmox is chosen only when every role those suites need has a runner online: all three for `all`, the two .NET roles for `dotnet`, `workspace-unit-auto` for `angular`. The reason lists each role's count, for example `dotnet-unit-auto 1 of 1`. The step emits `unit_labels`, `integration_labels` and `angular_labels`. The one-retry rule (ADR 0062) is unchanged.
- **Telemetry.** The separate `Telemetry` job is removed. On a one-runner role it held the runner for one job plus the restart gap. Build, integration and Angular print a `Show Runner` line instead: runner, host, cores and workspace.
- **The cache container** is renamed `cache-auto`.
- **Order of the switch.** The shared container `ci-lxc-runner-v6` (VMID 9503) keeps its three instances until this pipeline is on `master`, because `master` still asks for the labels `dotnet` and `angular`. Only after that are they deregistered and stopped. The container is kept (D86).

## Consequences

- Each kind runs one job at a time. The .NET build, the unit tests and the .NET cache save queue behind one another on `dotnet-unit-auto`.
- The whole run goes to GitHub-hosted when any role it needs is offline, even if the others are online.
- Three more containers draw on the thin pool `data`. They are thin, so space is written only as it is used.
- Two defects showed while the guests were created.
  - **The template pin.** An entry in `iac/tofu/stacks/guest/guests.yml` without `template_version` follows the newest template. After a template rebuild, the plan replaced three live guests. Every entry now pins its version.
  - **The disk size.** A clone was created at the template's 8 GiB. The first plan afterwards grows the disk in place to the flavor's size.
- Rollback:
  1. Revert the pull request.
  2. Converge the previous `ci-runner.yml` if the shared instances were already retired.
  3. Stop the three role containers. Never destroy them.
