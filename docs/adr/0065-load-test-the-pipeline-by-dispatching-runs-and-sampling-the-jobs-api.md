# 0065. Load-test the pipeline by dispatching runs and sampling the jobs API

- Status: Accepted
- Date: 2026-10-14
- Deciders: operator, for the owner's Phase 5 definition (D96)
- Decision log: D99 in docs/platform/requirements.md

## Context

D96 defines the Phase 5 load test.
- It runs .NET unit, .NET integration and Angular Jest concurrently, with 5 to 10 queued jobs per runner instance.
- It shows the cache reused and builds that reuse earlier outputs.
- It shows a failed run switching environment and re-queueing once.

The pipeline already reports a route reason, cache records and build numbers in its job logs (ADR 0062 to 0064). What was missing is a way to put many runs in the queue at once and to record what the queue and every attempt did.

## Options considered

1. **A workflow that dispatches the runs and polls.** It needs `actions: write` in this repository. A failure of the load test then becomes a red workflow on `master`.
2. **An external load tool against the runner's API.** GitHub assigns the jobs, so the runner has no queue of its own to load.
3. **A standard-library script, run by the operator,** that dispatches `sdet-ci.yml` on chosen refs and samples the jobs API until every run and its retry have settled. It then summarises from the same logs the pipeline writes.

## Decision

Option 3: `scripts/ci/load_test.py`.

- **`run --repository R --plan REF=COUNT ... --out FILE`.**
  - It dispatches each ref COUNT times.
  - Every 10 s it records the queued and running jobs, split by whether their labels include `proxmox`, and the online and busy Proxmox instances.
  - It stops after every dispatched run has completed and nothing has changed for 180 s, so a retry started by the callback is seen.
  - It then reads every attempt's jobs and the logs of `Select Runner`, `Build (.NET)` and `Test (Angular)`.
- **The report.**
  - The peak of queued Proxmox jobs divided by online instances.
  - Per run and attempt: the route, the build-output entries restored, the projects where CoreCompile ran and where it was skipped, the build time, and the jobs that failed.
- **The token.** It comes from `GH_TOKEN` and is sent only to the API host. The log download is redirected to storage, and the Authorization header is not carried along.
- **The load mix.** Refs carry one commit each on top of the branch under test:
  - a file outside every project (the selector runs every suite, every project reuses its outputs);
  - one changed project;
  - a changed `Directory.Build.props` (a full rebuild);
  - a unit test that fails only on the self-hosted runner (the retry on GitHub-hosted passes);
  - a unit test that always fails (the retry fails too, and the run is red).
- **The larger solution.** `tests/cache/bench_large_solution.sh`, dispatched through `cache-benchmark.yml`, measures the same reuse on a generated solution of 24 projects. It reports the median of three rounds for each scenario: cold, same tree, one leaf changed, a middle project changed, and with the commit id in the version.

## Consequences

- The load test needs an operator token with Administration read (the runners list) and Actions write (the dispatch). The repository grants no new permission.
- A load test costs one GitHub-hosted run for every Proxmox run that fails, as D95 intends.
- A dispatched run diffs against `HEAD~1`, so each load ref's top commit decides which suites run.
- The script reads the logs as text. A change to the route line, the cache records or the `[BENCHMARK]` lines must keep its tests passing (`tests/loadtest`).
