# 0060. Run own CI on one persistent runner container behind a job-start guard

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D93 in docs/platform/requirements.md
- Supersedes: part of [0054](0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md) (hosted runners for the repository's own runs)

## Context

The owner asked to run as much CI as possible on `pve01`, to keep fork pull requests open, to let only this repository's own Actions jobs use the machine, and to switch with a repository variable. ADR 0054 sent every run to hosted runners until the Phase 5 pool of JIT runners exists; that pool is handed off and not built. Until now no CI run had used the build cache, because hosted jobs run with `CACHE_URL` empty (ADR 0050).

Measured on the first runner, dispatch runs of the same commit (row 77):
- A job on the runner spends about 14 s on GitHub round trips, against about 3 s on a hosted runner. Set-up takes 4 to 5 s against 1 to 2 s; each action download is one request at 0.5 to 0.8 s. An artifact upload takes 4 s against 1 s. About 9 s pass after the last step against 2 s.
- Compute for this repository's small solution is about the same: compile 7 s against 6 to 11 s, affected tests 13 s against 14 to 16 s. Earlier the hosted test job looked twice as slow; it was rebuilding, because a hosted job starts on a fresh machine.
- After each job the listener stalls about 60 s before it takes the next one (actions/runner#4444).

## Options considered

1. Wait for the Phase 5 pool.
2. One persistent container with several runner instances, a job-start hook that refuses foreign events, and a variable that routes the caller workflow.
3. Ephemeral runners re-registered by a script after each job. This is a small controller: it needs a registration token per job and puts a full runner start on the critical path of every job.

## Decision

Option 2.
- Container `ci-lxc-runner-v6` (VMID 9503), flavor `aws/c5.2xlarge` (8 cores, 16 GiB), from `lxc-runner`. It is unprivileged, with its NIC on `guests` and the firewall flag set. The user `runner` has no sudo.
- Three instances, `pve01-ci-lxc-runner-1..3`, with labels `proxmox`, `dotnet` and `angular`. `iac/ansible/playbooks/ci-runner.yml` registers them, with the registration token on stdin.
- The job-started hook `scripts/ci/runner-guard.sh` fails a job before its first step unless the repository is this one and the event is `push`, `workflow_dispatch`, `schedule`, or `pull_request` from a branch of this repository (`tests/isolation/test-runner-guard.sh`).
- `.github/workflows/sdet-ci.yml:28` selects hosted runners unless `vars.CI_RUNNER` is `proxmox`. A fork pull request, or a dispatch with `force_ubuntu_runner` set to true, always runs hosted.
- A job-completed hook marks the instance, and a path unit restarts it once its worker has exited. This removes the #4444 stall.
- In `reusable-sdet-pipeline.yml`, .NET build and test run in one job, on both paths. The two jobs never shared binaries: a hosted job starts on a fresh machine, and with three instances the test job could land on another one. The cache save still depends only on the compile step (job output `compiled`). Untested: that a dependent job reads this output when the .NET job fails, since every measured run passed. If it cannot, a run whose tests fail skips the save, which costs one cold build and exposes nothing. `Report` runs on `ubuntu-latest` on both paths, because it only prints and a job on the runner costs about 10 s more.

## Consequences

- Wall time of `sdet-ci.yml` from dispatch runs, Proxmox against hosted. Before the .NET jobs were merged: 109 and 114 s against 74 and 79 s. After: median 66 s (63 to 72, five runs) against 58 s (48 to 76, five runs). The runner still trails hosted by about 8 s at the median, about one job's round-trip overhead, but its spread is 9 s against 28 s. It pays off where compute or the local cache dominates.
- The repository's own runs use the build cache. NuGet and `node_modules` restores hit on the runner. The save jobs run only after a push to `master`.
- The runner is persistent, not JIT: files outside the checkout survive between jobs on one instance. Only the owner can start an event the hook allows: the owner is the only collaborator, and Dependabot security updates are off. The Phase 5 gate "Runners are JIT and ephemeral before any pull-request job" is not met here; it remains a gate for the pool.
- To send every run back to hosted runners: `gh variable set CI_RUNNER --body hosted`. If the container is down, routed jobs queue for up to 24 hours until that is done. Removing the hook reopens "Untrusted execution" in `standard/blocking.md`.
- Workflows that need `python3 -m venv` stay on hosted runners, because the template has no `python3-venv`.
