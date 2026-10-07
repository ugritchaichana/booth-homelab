# 04. Transitive Affected Testing and Pipeline Layout

## Affected-test selector

`scripts/apps/dotnet-affected-test.sh` runs only the .NET test projects that a change can affect. It is the only implementation ([ADR 0056](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0056-keep-one-implementation-of-the-affected-test-selector.md)).

```mermaid
graph TD
    Diff["git diff --name-only base head"] --> Files["Changed files"]
    Files --> Owner["Owning .csproj of each file"]
    Owner --> Graph["Reverse closure over ProjectReference"]
    Graph --> Tests["Test projects inside the closure"]
    Tests --> Run["dotnet test on those projects only"]
```

Test projects are matched by file name (`*test*.csproj`), never by path, so a checkout directory with "test" in its name cannot widen the selection.

Fail-closed rules:

- A change to shared build configuration (`Directory.Build.props`, `Directory.Packages.props`, `nuget.config`, `global.json`, a `.sln`) selects every test project.
- A non-documentation change that maps to no project selects the full suite.
- A documentation-only change, or no change at all, exits 0 and runs nothing. With no committed change the script falls back to the working tree.

Example on the sample solution: a change under `src/Billing.Api/` selects `Billing.Api.UnitTests` and `Order.Api.IntegrationTests` (it references `Billing.Api`) and skips `Order.Api.UnitTests`; a change under `src/Core.Domain/` reaches `Order.Api` through `Core.Application` and selects the two Order test projects.

## Selector tests

`tests/verify-affected-graph.sh` checks the exact set of selected projects in disposable clones. `affected-selector-ci.yml` then runs it against three mutants of the selector; each must fail the named scenario, so the harness is not vacuous.

| Mutant | What it removes from the selector | Scenario that must fail |
|---|---|---|
| `drop-unmappable-block` | the whole branch for a change that maps to no project, including the documentation-only exit | docs only |
| `drop-unmappable-fallback` | the line that selects the full suite for an unmappable non-documentation change | unmappable change fails closed |
| `drop-shared-config-widening` | the line that selects every test project on a shared-config change | shared config plus mapped project |

Per-test detail: [docs/knowledge/test-catalogue.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/knowledge/test-catalogue.md).

## Pipeline layout

`sdet-ci.yml` handles `push`, `pull_request` and `workflow_dispatch` and calls the reusable workflow `reusable-sdet-pipeline.yml`. Cache numbers and the stale-binary rule: page 03.

```mermaid
graph LR
    S["Select Runner"] --> T["Telemetry"] & B["Build (.NET)"] & TD["Test (.NET)"] & CS["Cache save (.NET)"] & A["Test (Angular)"] & AS["Cache save (Angular)"] & R["Report"]
    T --> B
    B --> TD["Test (.NET)"]
    B --> CS["Cache save (.NET)"]
    TD --> CS
    A["Test (Angular)"] --> AS["Cache save (Angular)"]
    T --> R["Report"]
    B --> R
    TD --> R
    CS --> R
    AS --> R
    A --> R
```

The `select-runner` job picks the runner labels once; every other job needs it.

| Job | Restores | Saves |
|---|---|---|
| Build (.NET) | `nuget`, then `dotnet restore --locked-mode`, then `dotnet-outputs` | none; on a self-hosted default-branch push it packs the payloads as an artifact |
| Cache save (.NET) | none | `nuget`, `dotnet-outputs`; default-branch push on self-hosted runners only, environment `cache-writer` |
| Test (Angular) | `node_modules`, `npm ci` on a miss | none; on a self-hosted default-branch push it packs `node_modules` as an artifact |
| Cache save (Angular) | none | `node_modules`; same conditions as the .NET save |

Composite actions: `.github/actions/build-cache` (restore and save), `run-affected-tests` (the selector), `run-angular-jest`.

## Runner selection

The `select-runner` job chooses `ubuntu-latest` when `force_ubuntu_runner` is true or the repository is not this one, and the labels `self-hosted`, `linux`, `proxmox` and `dotnet` or `angular` otherwise. `CACHE_URL` is set only on the self-hosted path, so a hosted run executes with the cache disabled.

No self-hosted runner is online until the runner pool exists, so `sdet-ci.yml` forces hosted runners on push and pull request and defaults the dispatch input to true ([ADR 0054](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md)); the override is removed at the workflow cutover. Fork pull requests would reach the self-hosted labels through the expression alone: [docs/handoff/limits-and-gaps.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/limits-and-gaps.md).

## Other workflows

| Workflow | Runs on |
|---|---|
| `iac-ci.yml` | `iac/`, `tests/isolation/`: OpenTofu lint, validate and test; Ansible lint, syntax, isolation tests, Molecule |
| `cache-ci.yml` | `scripts/ci/build_cache/`, `tests/cache/`, `apps/`, the reusable pipeline: client tests, locked restores, stale-binary test |
| `evidence-ci.yml` | `docs/evidence/`, `docs/knowledge/`, `scripts/evidence/`, `tests/evidence/`: publisher tests and the published-text check |
| `affected-selector-ci.yml` | `scripts/apps/dotnet-affected-test.*`, `tests/`: selector harness and mutants |
| `hyperv-ci.yml` | `scripts/hyperv/`, `tests/hyperv/`: Pester tests of the Windows host layer |
| `secret-scan.yml` | every pull request and push to the default branch: gitleaks |
| `standard-scorecard.yml` | pull requests and pushes to the default branch, weekly: the scorecard and the documentation-claims check ([standard/README.md](https://github.com/ugritchaichana/booth-homelab/blob/master/standard/README.md)) |
| `sdet-fallback-drill.yml` | monthly: the full pipeline on hosted runners |
| `wiki-sync.yml` | `wiki/` on the default branch: mirrors the pages to the GitHub wiki |
| `pr-labeler.yml`, `pr-reviewer-guard.yml` | pull request events: area labels; removes an automatic reviewer request |
