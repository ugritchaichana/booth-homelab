# 0064. Build .NET once, test unit and integration as parallel jobs, and give every runner instance one path

- Status: Accepted; amends the job layout of [0060](0060-run-own-ci-on-one-persistent-runner-container-behind-a-job-start-guard.md)
- Date: 2026-10-14
- Deciders: operator, for the owner's Phase 5 definition (D96)
- Decision log: D98 in docs/platform/requirements.md

## Context

D96 asks for a load test that runs .NET unit, .NET integration and Angular Jest concurrently. It also asks that builds reuse earlier cached outputs ([ADR 0063](0063-cache-build-outputs-per-project-and-keep-the-commit-id-out-of-the-version.md)). Three facts stood in the way.

- **One job does everything.** `Build and Test (.NET)` built the solution and then ran every affected test project in sequence. Unit and integration suites could not run side by side.
- **Each suite rebuilt.** The selector ran `dotnet test <project>` without `--no-build`, so each suite rebuilt its project after the solution build. In WSL a suite took 4.4 s that way, against 1.4 s with `--no-build`. A test assembly copied to another directory ran there in 1.2 s with `dotnet test <assembly>`.
- **The cache is per instance.** The three runner instances live in `/opt/actions-runner-1..3`, so each has its own workspace path, and build outputs are keyed by the workspace that built them (ADR 0049, row 79). An entry saved from instance 2 can never serve instance 1 or 3. In 12 live runs, instance 3 missed the outputs cache 4 times out of 4.

## Options considered

1. **Run the test projects in parallel inside the one job** (`dotnet test` on the solution). The suites stay on one runner instance, so the load test cannot spread them, and a test failure still says nothing about which kind failed.
2. **Have each test job restore and build what it needs.** This works through the per-project cache, but every pull request builds its changed projects once per test job.
3. **Build once, hand the test assemblies over, and test per kind.** Run every instance from one path.

## Decision

Option 3.

- **`Build (.NET)` (job `dotnet`).** It restores the caches and builds once. It counts the projects where CoreCompile ran and where it was skipped (`compiled_projects`, `reused_projects`, from a detailed file log). The selector's new list mode (`AFFECTED_LIST_FILE`) names the affected test projects without running them. Those are split into `affected-unit.txt` and `affected-integration.txt`, by the `IntegrationTests` project-name suffix. The `bin` folders of the affected test projects are uploaded with both lists as the artifact `dotnet-test-bin`, kept one day.
- **`Test (.NET unit)` and `Test (.NET integration)`.** Each needs the build and is skipped when its list is empty. It downloads `dotnet-test-bin` and runs `scripts/apps/dotnet-run-tests.sh <list>`, which calls `dotnet test <assembly>` for each project and does not build. Each job uploads its TRX files as `sdet-dotnet-unit-results` or `sdet-dotnet-integration-results`. The report downloads both, and still accepts the old `sdet-dotnet-test-results`.
- **`Test (Angular)`.** No change. It already ran beside the .NET job.
- **The `Report` job** fails when the build or Angular job did not succeed, or when a test job ended in anything other than success or skipped.
- **One runner path.** The unit `actions-runner@.service` binds the instance directory onto the shared path (`BindPaths=/opt/actions-runner-%i:/opt/actions-runner`) and starts the runner from there. Every instance then works in `/opt/actions-runner/_work/...`, so an outputs entry saved from any instance matches every other. systemd binds the path in a private mount namespace per service, which works in the unprivileged container without nesting (probed on the runner template's demo clone). `runner-restart.sh` used to find a busy worker by its command line, which every instance now shares. It now finds the worker by the unit's cgroup.
  - Each unit also gets a private `/tmp` (`PrivateTmp=yes`). MSBuild nodes and the compiler server are found through sockets in `/tmp`. With one shared path and a shared `/tmp`, a build on one instance could run in a process of another instance, which sees a different directory at the same path. The preliminary load test showed this: one build skipped CoreCompile in 2 projects although every outputs entry missed, then failed with MSB3030 (run 38516088499).

## Consequences

- Unit and integration suites run concurrently with Angular Jest, on whichever runner instances are free.
- No test job compiles, and a suite starts from built assemblies.
- The artifact round trip through GitHub's storage adds a few seconds per run. It is measured in the Phase 5 load test.
- The project-name suffix decides the kind. A test project named otherwise counts as unit. Its results are still reported, but not under integration.
- The pull-request comment shows the new result artifacts once the callback on `master` carries the new `sdet-report.sh`. Runs made before the merge still report through the old name.
- An outputs entry saved by one instance serves all three. The first runs after the unit change miss, because the key root changed. The next `master` push saves entries under the shared path.
- If a host ever forbids private mount namespaces, the runner unit fails to start. The router then sends runs to GitHub-hosted (ADR 0062), and the rollback is the previous unit file.
