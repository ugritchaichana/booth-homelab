# 09. Actions Janitor

**Status:** Active once merged to `master`
**Files:** `.github/workflows/actions-janitor.yml`, `scripts/ci/actions_janitor.sh`

---

## 1. What it does

The self-hosted runners (`pve-runner-01`, `pve-runner-angular`) can go offline. While they are offline every push and pull request queues jobs on the `self-hosted` labels that never start. GitHub cancels a queued job only after 24 hours, so stuck runs pile up until then.

The janitor runs on a GitHub-hosted runner (`ubuntu-latest`), so it works while the self-hosted runners are down. Every 15 minutes it:

1. Lists runs that are `queued` or `in_progress` and reads the jobs of each.
2. Decides whether the self-hosted runners are alive (section 3).
3. Cancels runs that are stuck only because the runners are offline (section 2).
4. Opens or updates a GitHub issue titled `CI: self-hosted runners offline — queued runs auto-cancelled`, label `ci-runner-offline`, and closes it when a self-hosted job runs again.

Each decision is printed as a `::notice::` line and as a table in the job summary. The last log line of every tick is a one-line summary with the runner state and the method that decided it.

## 2. Exact cancel conditions

A run is cancelled only when all of these hold:

- The run is `queued` or `in_progress` and is not the janitor's own run.
- It has at least one job with status `queued` whose labels include `self-hosted`, created more than `stale_minutes` ago.
- It has no job `in_progress`.
- It has no `queued` job without the `self-hosted` label (a hosted job waiting for capacity is never cancelled).
- The runners are not alive.

Plain `POST /actions/runs/{id}/cancel` is used. `force-cancel` is used instead only when the run already shows a cancel: at least one job is `completed` with conclusion `cancelled`, every job that has started is `completed`, a self-hosted job is still `queued` (typically a job with `if: always()` that re-queued after the cancel), and the run has not been updated for more than `stale_minutes`.

A run that was cancelled by hand less than `stale_minutes` ago and has such a re-queued job takes the plain `cancel` first. If GitHub rejects that call, the tick logs a warning, exits non-zero, and a later tick takes the force path once the run has been idle long enough.

## 3. How runner state is decided

The state is one of `ALIVE`, `OFFLINE`, `UNKNOWN`. Nothing is cancelled unless it is `OFFLINE`.

| Method | When | Alive means |
|---|---|---|
| Runners API | `RUNNER_ADMIN_READ_TOKEN` secret is set and the call succeeds | `GET /repos/{repo}/actions/runners` lists at least one runner with status `online` |
| Job activity | no token, or the API call failed (a warning is printed) | a job whose labels include `self-hosted` has a non-empty `runner_name` and is in progress, or started or completed within the last `stale_minutes` |

With the job-activity method:

- `OFFLINE` is declared only when a stuck queued self-hosted job exists. With nothing queued and no recent activity the state is `UNKNOWN`, because idle runners and offline runners look the same from job data alone. Nothing is cancelled and an open alert issue stays open.
- Cancelled jobs that never ran carry an empty `runner_name` and a `started_at` equal to their creation time. The `runner_name` check keeps them from counting as activity.
- Only runs updated within the last `stale_minutes`, plus runs in progress, are inspected, and at most 40 of them.

Any one online runner counts as alive, whatever its labels. If only one of the two runners is down (for example `angular` is down while `dotnet` still runs jobs), jobs for the down runner stay queued and the janitor holds back. The 24 hour GitHub limit still applies to those jobs.

## 4. The alert issue

- A tick that cancels at least one run creates the issue if none is open, or adds a comment listing run ids, workflows and queue ages.
- A tick that finds the runners `ALIVE` while an issue is open comments with the evidence (job id, runner name, time, or the online runner names) and closes the issue.
- The `ci-runner-offline` label is created on first use.

## 5. Tuning `stale_minutes`

`stale_minutes` (default 30) is used in three places: the minimum queue age of a self-hosted job, the window in which job activity counts as alive, and the idle time before `force-cancel`.

- Lower it to clear stuck runs sooner. A value shorter than a normal queue wait can cancel runs that would have started. While a self-hosted job is in progress the runners count as alive and nothing is cancelled.
- Raise it to be more conservative.
- Set it for one manual run: `gh workflow run actions-janitor.yml -f stale_minutes=45 -f dry_run=true`.
- The schedule uses the default. Change the default in `actions-janitor.yml` to change it permanently.

## 6. Optional secret: `RUNNER_ADMIN_READ_TOKEN`

Without it the janitor uses job activity. With it the janitor reads the real runner status. The default `GITHUB_TOKEN` cannot list runners.

1. Create a fine-grained personal access token. Resource owner: the repository owner. Repository access: only `booth-homelab`. Repository permission: Administration, read-only. Set an expiry.
2. Store it: `gh secret set RUNNER_ADMIN_READ_TOKEN --repo ugritchaichana/booth-homelab`
3. No workflow change is needed. If the token expires or is revoked the janitor prints a warning and falls back to job activity.

## 7. Dry run, manual run, disable

- Pull requests that touch the workflow or the script always run in dry-run: the script prints what it would do and issues no write call.
- Manual dry run: `gh workflow run actions-janitor.yml -f dry_run=true`
- Disable the schedule: `gh workflow disable actions-janitor.yml`
- Enable it again: `gh workflow enable actions-janitor.yml`

All write calls (cancel, force-cancel, label, issue, comment) go through one function in the script that returns before calling the API when dry-run is on.

## 8. Known limits

- A `wiki-sync.yml` run queued while the runners are offline is cancelled like any other self-hosted run, so the wiki is not synchronized for that push. Re-run it with `gh workflow run wiki-sync.yml` once the runners are back.
- At most 100 queued and 100 in-progress runs are read per tick.
- The runners are offline from the janitor's point of view only after a self-hosted job has been queued for longer than `stale_minutes`.
