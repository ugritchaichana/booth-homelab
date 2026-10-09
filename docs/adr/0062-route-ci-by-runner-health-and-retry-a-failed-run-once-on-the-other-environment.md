# 0062. Route CI by runner health and retry a failed run once on the other environment

- Status: Accepted
- Date: 2026-10-08, amended by the owner 2026-10-09 before merge
- Deciders: owner
- Decision log: D95 in docs/platform/requirements.md

## Context

Since ADR 0060 the SDET pipeline runs on one Proxmox runner container when the repository variable `CI_RUNNER` is `proxmox`. The variable was the only input:

- with the container down, every routed job waited in the queue for up to 24 hours until someone changed the variable;
- a failed run stayed red even when a second try on a different environment would have told a broken runner from broken code.

The owner asked for a router with these rules:

- check whether the on-premises runner is usable before queueing, and use it whenever it is, even when every instance is busy, to keep cost down;
- use GitHub-hosted runners when it is not usable;
- retry a failed run once, automatically, on the other environment:
  - the first run is attempt 0 and the retry is attempt 1 (GitHub's `run_attempt` 1 and 2);
  - if the retry fails too, the run is red;
- add no watchdog.

The first version retried only a run with an infra fingerprint. On 2026-10-09 the owner widened the retry to any cause and set the target to the other environment.

## Options considered

1. **The variable alone.** No code, but every outage needs a person.
2. **A watchdog.** Queue on Proxmox, then cancel and re-dispatch to hosted after a deadline. No API moves a queued job, so this is the only way to rescue a job that is already queued ([next-phases.md](../handoff/next-phases.md), overflow research). The owner declined it.
3. **A health check before queueing, plus one retry of a failed run on the other environment.**

For the health check, the GitHub runners API was chosen over probing the container: a hosted job cannot reach the lab network.

## Decision

Option 3.

### The route (`Select Runner`)

`scripts/ci/select-runner.sh` and `scripts/ci/runner_route.py` (standard library only) decide the route, in this order:

1. **Forced hosted.** A fork, `CI_RUNNER` other than `proxmox`, or the dispatch input: GitHub-hosted, on every attempt.
2. **Rerun of an attempt on Proxmox.** The previous attempt is read first. If it ran on Proxmox, the rerun goes to GitHub-hosted, whatever the cause.
3. **Health check.** This covers attempt 1, and a rerun of an attempt on GitHub-hosted. It calls `GET /repos/{repo}/actions/runners` with the secret `RUNNER_STATUS_TOKEN`:
   - at least one runner labelled `proxmox` is `online`: Proxmox, busy or not;
   - none is online: GitHub-hosted;
   - no token, an HTTP error, or an unreadable document: `CI_RUNNER` decides, and the reason says so.

The token is a fine-grained token on this repository only, with Administration read. It reaches the route step's environment and nothing else, through `secrets: inherit`. Declaring it under `workflow_call` would make actionlint require `CACHE_WRITER_PASSWORD` too, an environment secret that `workflow_call` cannot pass.

The reason is printed in the job log, the step summary and the `Report` job's Routing line, for example `3 of 3 Proxmox runners online (HTTP 200)`.

`CACHE_URL` and `BUILD_CACHE_RUNNER_CLASS` moved from workflow env to job env keyed on the route, so a run routed to hosted never probes the private cache address.

### The retry (`sdet-callback.yml`)

The callback runs three jobs, each with its own permissions; the workflow grants none:

1. **classify** (read only, `scripts/ci/sdet-classify.sh`). It reads the finished attempt and the one before it.
2. **report**. Unchanged, plus one `Runner:` line saying why the run was or was not retried.
3. **retry** (`actions: write` only). It runs `gh run rerun <id>`, for the whole run, once, after the report has read the attempt's artifacts.

The retry rules:

- **What is retried.** Attempt 1 with conclusion `failure` or `timed_out`, whatever the cause and wherever it ran. Attempt 1 with conclusion `cancelled` is retried only when a Proxmox job lost its runner. A runner lost in the Angular job (run 37883774581) left that job and the whole run `cancelled`, with the annotation "The operation was canceled.".
- **What is not.** `success` and `startup_failure` (a run that never started cannot be rerun) are never retried, and neither is attempt 2 or later. A run cancelled on purpose is not retried either: a person's cancel leaves "The run was canceled by @user." on its jobs (run 37883999894), and a concurrency cancel leaves "Canceling since a higher priority waiting request ... exists" (documented, not measured).
- **Why the whole run.** `--failed` would reuse the first attempt's `Select Runner` outputs and land on the same environment again.

### The cause label

Every failed attempt gets a cause in the comment:

- the infra fingerprint when there is one;
- otherwise the first failed job and step, skipping the derived `Report` job.

The fingerprint no longer gates the retry; it tells the pull-request author whether the runner or the code failed.

| Signal | Label | Source |
|---|---|---|
| The job failed with a runner assigned, a step ended `cancelled`, and no step failed | runner lost | measured twice: runner instance 1 restarted during the .NET test step (run 37766869178), then instance 2 (run 37772130618) |
| The job was cancelled with a step `cancelled`, no step failed, and the annotation "The operation was canceled.", with no deliberate-cancel annotation in the run | runner lost | measured: instance 1 restarted during the Angular Jest step (run 37883774581) |
| An annotation says "The runner has received a shutdown signal" or "lost communication with the server" | runner lost | documented by GitHub, not measured |
| The job failed with no runner assigned, or its first failed step is `Set up job` or a checkout | runner or setup | documented, not measured |
| A timeout, or a test, compile or `Set up runner` step failed | the failing job and step | measured: run 37758605391 |

### Comment notes

| After | Note |
|---|---|
| Attempt 1 fails | "Attempt 1 failed on <environment> (<cause>); the whole run is rerun once, on the other environment unless it must stay on GitHub-hosted." |
| Attempt 2 passes | The header reads "passed on attempt 2", and the note: "Passed on retry: attempt 1 failed on ... (...); attempt 2 passed on ...". |
| Attempt 2 fails | "Failed again: ...; attempt 2 failed on ... (...). No further retry, so the run is red." |

## Consequences

- **Phase 5 is not done by this.** Its DONE WHEN (requirements section 5) is being redefined by the owner and is recorded separately. This decision covers routing and the retry for the persistent container. Two R8 lines differ by the owner's choice, for this container:
  - a busy runner keeps the run on Proxmox, where R8 overflows a saturated pool;
  - there is no deadline overflow, where R8 says "a job waiting past a deadline overflows to hosted".

  The Phase 5 work revisits both.
- **A flaky test can pass on the retry.** The owner accepted this. The signal is the header "passed on attempt 2" with the Runner line, which names attempt 1's environment and cause; attempt 1's logs stay on the run page.
- **Cost.** Every failed run on Proxmox now costs one GitHub-hosted run, a real test failure included, and a red run takes two runs to report red. A fork's rerun executes its code again on hosted with the same read-only token.
- **No watchdog, by decision.** A job that `Select Runner` already sent to Proxmox waits for up to 24 hours if the container dies before picking it up. Cancel and rerun it: the rerun reads the cancelled attempt and switches environment.
- **Token expiry.** When the token expires the check returns 401 and routing falls back to `CI_RUNNER`, with the status in the summary. Rotation is in runbook 3.7.
- **Token exposure.** Any workflow on a branch of this repository can read the token; forks never receive it. This rests on the owner being the only collaborator (security model).
- **Rerun attempts trigger the callback.** A rerun started with `GITHUB_TOKEN` still fires `workflow_run` when it completes: attempt 2 of run 37772130618 fired callback 37772441144 two seconds after it ended. The comment therefore shows the retried attempt.
- **Testing a change before merge.** Replay the callback from the branch with `gh workflow run sdet-callback.yml --ref <branch> -f run_id=<id>`, which runs all three jobs. Until this merges, `master`'s older callback also comments on every failed run.
- **Coverage.** `runner_route.py` and `run_report.py` are held at 100% line, branch and condition coverage in CI. `tests/condition_coverage.py` measures conditions, which coverage.py does not. The three shell scripts reach 100% line coverage under kcov, locally only ([coverage.md](../knowledge/coverage.md)).
- **To turn it off.** Delete the secret to route by `CI_RUNNER` alone, or run `gh workflow disable sdet-callback.yml` to stop the retry.
- **Evidence.** [router-live-runs.txt](../evidence/closeout/router-live-runs.txt).
