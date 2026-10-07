# 08. Runtime Support and Upgrade Plan

Each pinned runtime that is past, or within 30 days of, its vendor's end of security support, with the upgrade order. A component within 30 days of its end date with no plan in the repository counts as unsupported. Dates were read from `endoflife.date` on 2026-10-05; re-check them before relying on them (commands at the end). A date not listed here is not recorded in the repository.

## Component plan

| Component | Pinned where | Vendor end of security support | State |
|---|---|---|---|
| Proxmox VE | PVE 9.2 on `pve01` (pve-manager 9.2.21), upgraded from the 9.1 installer ISO by the `pve_host` role ([ADR 0005](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0005-use-the-no-subscription-repository-and-upgrade-through-ansible.md)) | not recorded | Current. PVE 8.4 ended 2026-08-31 and was the retired host's version; whether it still blocks the standard: [standard/blocking.md](https://github.com/ugritchaichana/booth-homelab/blob/master/standard/blocking.md) |
| .NET 8 | `apps/backend/**/*.csproj` (`net8.0`); `dotnet-version: '8.0.x'` in the workflows; SDK 8 in the `lxc-runner` template | 2026-11-10 | Within 30 days of its end from 2026-10-11. The `lxc-runner` template already carries SDK 10 next to SDK 8, so the runner image part of the upgrade is done |
| .NET 10 | SDK in the `lxc-runner` template bundle `versions.yml` | 2028-11-14 | Target |
| Node.js 22 | `lxc-runner` template bundle, `node-version: '22.x'` in the workflows, `@types/node` in `apps/frontend/package.json` | 2027-04-30 | Supported. Node 20 ended 2026-04-30 and is no longer pinned |
| Debian 13 | Base of both template classes and the cache container | not recorded | Current |

## .NET 8 to 10 checklist

Order: runner image (done), then the retarget and package bumps in one change, then the workflow pins, then remove SDK 8 from the template.

- [ ] `TargetFramework` `net8.0` to `net10.0` in every `.csproj` under `apps/backend/src` and `apps/backend/tests`.
- [ ] Test packages in the three test projects: `Microsoft.NET.Test.Sdk` 17.8.0 predates .NET 10 and is bumped during the retarget; check `xunit` and `xunit.runner.visualstudio` 2.5.3 and `coverlet.collector` 6.0.0 against the .NET 10 SDK and bump if test discovery or coverage fails.
- [ ] `dotnet-version: '8.0.x'` to `'10.0.x'` in `reusable-sdet-pipeline.yml`, `affected-selector-ci.yml` and `cache-ci.yml`.
- [ ] Regenerate every `packages.lock.json` (the build cache keys on them and the pipeline restores in locked mode).
- [ ] After the repository stops targeting 8.0.x, remove `dotnet_sdk_8` from the `lxc-runner` `versions.yml` and the matching assert in its playbook, in one pull request ([RUNBOOK.md](https://github.com/ugritchaichana/booth-homelab/blob/master/RUNBOOK.md), "Day-2 operations", "Golden templates", "Bump a pinned toolchain in `lxc-runner`").
- [ ] Update the .NET 8 mentions in this page and in `apps/README.md`.

## How to re-check

```sh
curl -s https://endoflife.date/api/proxmox-ve.json
curl -s https://endoflife.date/api/nodejs.json
curl -s https://endoflife.date/api/dotnet.json
curl -s https://endoflife.date/api/debian.json
```

Compare the `eol` field of each cycle with the pins above and update the table when a pin or a date changes.
