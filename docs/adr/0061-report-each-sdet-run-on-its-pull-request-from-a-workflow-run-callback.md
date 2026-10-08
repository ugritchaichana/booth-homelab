# 0061. Report each SDET run on its pull request from a workflow_run callback

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D94 in docs/platform/requirements.md

## Context

The owner asked that every finished test run post its result on the pull request: the pass rate, the failed tests, and the error log of each failure, so the author can see why it broke. The run's own job summary already shows durations and cache hits, but nobody reads it from the pull request page. It has no failed-test list and no logs.

A `pull_request` run started from a fork gets a read-only `GITHUB_TOKEN` and no secrets. A job inside the SDET pipeline therefore cannot comment on a fork's pull request, and fork pull requests are open to anyone in this lab (ADR 0059).

## Options considered

1. Comment from the pipeline's `Report` job. This works for branches of this repository but fails silently for forks.
2. A third-party test-report action. It adds a supply-chain dependency that runs with a write token, and most such actions report through check runs rather than a comment.
3. A separate workflow on `workflow_run` of the pipeline, running the default branch's code with its own token, with a parser in this repository.

## Decision

Option 3: `.github/workflows/sdet-callback.yml`, job `Report to the pull request`, on hosted runners.

- **Inputs.** It reads the finished run through the API: the run, the jobs of its latest attempt, the `.trx` files (`sdet-dotnet-test-results`), the Jest JSON (`sdet-angular-results`, written by `scripts/apps/run-angular-jest.sh`), and the logs of failed jobs and of the two test jobs. Cache hits come from the cache client's JSON records in those logs.
- **Parser.** `scripts/ci/run_report.py` (standard library only) renders one comment:
  - per suite: passed, failed and skipped, the pass rate (passed over executed) and the execution rate;
  - every failed test with its message and the first lines of its stack;
  - every failed job whose failure no test explains, with the failing step and the last 40 log lines;
  - links to the run and the job logs.
- **One comment per pull request.** It is found by a hidden marker and the bot author, then updated in place.
- **Pull request resolution.** The open pull request whose head SHA and head repository equal the run's head. A number written by the run is never trusted, because a fork controls its own workflow files.
- **Untrusted text.** Every input may come from a fork and reaches a job that holds a write token:
  - files are capped at 5 MB;
  - free text sits in code fences longer than any backtick run inside it;
  - `@` is neutralized outside fences;
  - the body stays under 60,000 characters, with a truncation line;
  - run values reach the script only through `env`;
  - the job never checks out the run's code.
- **Language.** The comment is in English (repository rule).

## Consequences

- Fork pull requests get the same report as branches of this repository.
- `workflow_run` fires only from the default branch's copy of the workflow. Before a change merges, replay it by hand with `gh workflow run sdet-callback.yml -f run_id=<run id>`.
- A run whose head is no open pull request's head (a push to `master`) writes the report to the callback's job summary only. A dispatched run on a pull request's head updates that pull request's comment.
- Only the SDET pipeline is reported. The other workflows keep their own summaries.
- The runner router's planned retry on an infra failure belongs in this callback too ([next-phases.md](../handoff/next-phases.md), overflow to hosted).
- To turn it off: `gh workflow disable sdet-callback.yml`.
