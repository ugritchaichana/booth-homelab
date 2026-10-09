# 0062. Route CI by runner health and retry once on hosted after an infra failure

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D95 in docs/platform/requirements.md

## Context

Since ADR 0060 the SDET pipeline runs on one Proxmox runner container when the repository variable `CI_RUNNER` is `proxmox`. The variable was the only input:

- with the container down, every routed job waited in the queue for up to 24 hours until someone changed the variable;
- a runner lost in the middle of a job turned the run red although no code was at fault.

The owner asked for a router with these rules:

- check whether the on-premises runner is usable before queueing, and use it whenever it is, even when every instance is busy, to keep cost down;
- use GitHub-hosted runners only when it is not usable, or when a run fails because the runner itself broke;
- retry such a run once, automatically, on the other environment;
- add no watchdog.

## Options considered

1. **The variable alone.** No code, but every outage needs a person.
2. **A watchdog.** Queue on Proxmox, then cancel and re-dispatch to hosted after a deadline. No API moves a queued job, so this is the only way to rescue a job that is already queued ([next-phases.md](../handoff/next-phases.md), overflow research). The owner declined it.
3. **A health check before queueing, plus one retry on hosted after an infra fingerprint.**

For the health check, the GitHub runners API was chosen over probing the container: a hosted job cannot reach the lab network.

## Decision

Option 3.

### The route (`Select Runner`)

`scripts/ci/select-runner.sh` and `scripts/ci/runner_route.py` (standard library only) decide the route, in this order:

1. **Forced hosted.** A fork, `CI_RUNNER` other than `proxmox`, or the dispatch input: GitHub-hosted, as before.
2. **Rerun.** On attempt 2 or later, the previous attempt is classified first. An infra fingerprint routes the rerun to GitHub-hosted.
3. **Health check.** `GET /repos/{repo}/actions/runners` with the secret `RUNNER_STATUS_TOKEN`:
   - at least one runner labelled `proxmox` is `online`: Proxmox, busy or not;
   - none is online: GitHub-hosted;
   - no token, an HTTP error, or an unreadable document: `CI_RUNNER` decides, and the reason says so.

The token is a fine-grained token on this repository only, with Administration read. It reaches the route step's environment and nothing else, through `secrets: inherit` (declaring it under `workflow_call` would make actionlint require `CACHE_WRITER_PASSWORD` too, an environment secret that `workflow_call` cannot pass).

The reason is printed in the job log, the step summary and the `Report` job's Routing line, for example `3 of 3 Proxmox runners online (HTTP 200)`.

`CACHE_URL` and `BUILD_CACHE_RUNNER_CLASS` moved from workflow env to job env keyed on the route, so a run routed to hosted never probes the private cache address.

### Infra fingerprint

Only failed jobs whose labels include `proxmox` count. A real failure in any of them vetoes the retry. When unsure, it is not infra.

| Signal | Verdict | Source |
|---|---|---|
| The job failed with a runner assigned, a step ended `cancelled`, and no step failed | infra | measured twice: runner instance 1 restarted during the .NET test step (run 37766869178), then instance 2 (run 37772130618) |
| An annotation says "The runner has received a shutdown signal" or "lost communication with the server" | infra | documented by GitHub, not measured |
| The job failed with no runner assigned | infra | documented, not measured |
| The first failed step is `Set up job` or starts with `Checkout` | infra | documented, not measured |
| An annotation says "exceeded the maximum execution time" | not infra: a timeout | documented |
| A test, compile or `Set up runner` step failed | not infra: the code, or the job-start guard's policy | measured: run 37758605391 is the negative fixture |

### The retry (`sdet-callback.yml`)

The callback runs three jobs, each with its own permissions; the workflow grants none:

1. **classify** (read only, `scripts/ci/sdet-classify.sh`). It reads the finished attempt and the one before it.
2. **report**. Unchanged, plus one `Runner:` line saying why the run was or was not retried.
3. **retry** (`actions: write` only). It runs `gh run rerun <id>`, for the whole run, once, after the report has read the attempt's artifacts.

It retries only attempt 1 of a failed run that ran on Proxmox with an infra fingerprint. A whole-run rerun is required: `--failed` would reuse the first attempt's `Select Runner` outputs and land on Proxmox again.

## Consequences

- **Cost.** GitHub-hosted minutes are spent only when no Proxmox runner is online or after an infra failure.
- **No watchdog, by decision.** A job that `Select Runner` already sent to Proxmox waits for up to 24 hours if the container dies before picking it up. Cancel and rerun it: the rerun health-checks again.
- **Token expiry.** When the token expires the check returns 401 and routing falls back to `CI_RUNNER`, with the status in the summary. Rotation is in runbook 3.7.
- **Token exposure.** Any workflow on a branch of this repository can read the token; forks never receive it. This rests on the owner being the only collaborator (security model).
- **Rerun attempts trigger the callback.** A rerun started with `GITHUB_TOKEN` still fires `workflow_run` when it completes: attempt 2 of run 37772130618 fired callback 37772441144 two seconds after it ended. The comment therefore shows the retried attempt.
- **Testing a change before merge.** Replay the callback from the branch with `gh workflow run sdet-callback.yml --ref <branch> -f run_id=<id>`, which runs all three jobs.
- **Coverage.** `runner_route.py` and `run_report.py` are held at 100% line, branch and condition coverage in CI. `tests/condition_coverage.py` measures conditions, which coverage.py does not. The three shell scripts reach 100% line coverage under kcov, locally only ([coverage.md](../knowledge/coverage.md)).
- **To turn it off.** Delete the secret to route by `CI_RUNNER` alone, or run `gh workflow disable sdet-callback.yml` to stop the retry.
- **Evidence.** [router-live-runs.txt](../evidence/closeout/router-live-runs.txt).
