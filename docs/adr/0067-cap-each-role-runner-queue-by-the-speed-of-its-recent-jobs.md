# 0067. Cap each role runner's queue by the speed of its recent jobs

- Status: Accepted
- Date: 2026-10-14
- Deciders: owner
- Decision log: D101 in docs/platform/requirements.md
- Amends: 0062 (the health check), 0066 (routing per role)

## Context

Each test kind has one runner (ADR 0066), and that runner takes one job at a time. A job waits in its runner's queue, and nothing limits that queue. GitHub keeps a queued job for up to 24 hours.

Load round 6 measured a cycle of 48 to 52 s per job on each role runner. At that pace, 15 queued jobs mean a wait of 12 to 13 minutes. A whole run on GitHub-hosted takes about 71 s.

The owner set these terms:
- A ceiling of 15.
- The ceiling follows the state of the Proxmox host, including other containers that use its resources.
- A job already in the queue is never cancelled.
- The host is Proxmox on Linux. The Windows machine of the reference lab is not part of the design.

`Select Runner` runs on GitHub-hosted, so it cannot read the host's load directly.

## Options considered

1. **No ceiling.** The queue and the wait grow without bound.
2. **A fixed ceiling of 15.** It ignores the host's state, so a busy host keeps taking 15 jobs, each of them slower.
3. **The host publishes its load** (pressure, free memory) to a repository variable. It needs a credential with write access on the host, and a timer that can stop silently.
4. **The host stops a runner when it is busy.** That is all or nothing, and jobs already queued wait until the runner returns.
5. **Derive the ceiling from how fast the role's recent jobs ran.** A busy host makes jobs slower, and slower jobs lower the ceiling. It needs no host access and no new credential.

## Decision

Option 5.

- **Per role,** for the roles the run's suites need (ADR 0066):
  - **Job time:** the median duration of the role's 5 most recent completed jobs, plus a 10 s restart gap. Skipped jobs and jobs without both timestamps are left out. Without history, the job time is 50 s, the measured cycle.
  - **Ceiling:** the accepted wait divided by the job time, rounded down, at most the cap, at least 1.
  - **Queue:**
    - the role's jobs that are `queued`, `waiting` or `pending` in other open SDET runs;
    - plus the jobs an unfinished `Build (.NET)` on `dotnet-unit-auto` will create, which is one unit job and one integration job;
    - plus one for every other run whose `Select Runner` has not finished. Such a run has no queued job yet, and it may take one. Load round 7 showed why this matters: three runs dispatched 4 s apart each read `12/13` and all three joined, so the real queue reached 15 under a ceiling of 13.
- **Routing.**
  - When the health check would choose Proxmox and any needed role has a queue at or above its ceiling, the whole new run goes to GitHub-hosted. The reason names that role, as in `queue full for workspace-unit-auto (... workspace-unit-auto 15/15 @50s ...)`.
  - Jobs already queued are never cancelled or moved.
  - The rule applies to a first attempt and to a rerun after GitHub-hosted. A rerun after Proxmox goes to GitHub-hosted anyway (ADR 0062).
- **Settings.** Two repository variables:
  - `RUNNER_QUEUE_WAIT_S` is the accepted wait, 750 s by default.
  - `RUNNER_QUEUE_CEILING` is the cap, 15 by default.
- **Data.** `Select Runner` uses the workflow token, which can read actions.
  1. One list of the 100 most recent runs.
  2. The jobs of each open run of a workflow that calls the pipeline (`sdet-ci.yml`, `sdet-fallback-drill.yml`), except the run itself. The callback workflow is left out: its jobs never run on Proxmox, and its runs, being the latest to finish, would hide the history.
  3. The jobs of the 3 most recent completed runs of those workflows.

  That is 4 calls plus one per open run. The workflow token allows 1,000 requests per hour per repository. If any call fails, the ceiling is skipped, the run is routed by health alone, and the reason says why.

## Consequences

- The ceiling reacts after the fact: jobs must first run slower before it drops.
- Counting runs that are still choosing a runner errs on the safe side. A run that is still choosing counts for every role, even one it does not need, so a new run can be sent to GitHub-hosted slightly early. Two runs that read the queue within the same second can still both join.
- Jobs that do not belong to an SDET run (a benchmark dispatched on Proxmox) are not counted.
- A run of 25 dispatches costs about 400 API calls in its hour. A failed call costs only the ceiling, never the run.
- Rollback: set `RUNNER_QUEUE_CEILING` to a large value, or revert the pull request.
