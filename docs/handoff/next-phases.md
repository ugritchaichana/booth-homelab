# Next phases (5-8)

Phases 5 to 8 are planned, not started (requirements.md section 5). Each work package gives the goal, the DONE WHEN clause as written in the requirements, the entry gates and the owner steps. Before starting a phase, write its blast-radius estimate in four counted dimensions (what breaks and how many, furthest environment reached, time to detect, time to roll back and who) and answer the security pre-flight (requirements.md sections 7.1 and 7.2 are the model). If time to detect exceeds time to roll back, add signal before starting.

Working rules that carry over: write tests red first and mutation-test queue, scale and key logic; layer the controller as domain, application, infrastructure with a test that fails when the domain imports infrastructure; record every finalized decision as an ADR in the pull request that makes it; keep pull requests at 30 files or fewer; never narrow a check to go faster.

Effort for the receiving team is unknown: measure the first work package of Phase 5 and re-plan from it.

## Phase 5: Runner pool controller

**Goal.** A JIT ephemeral runner per job, scaling with queue depth inside host CPU, RAM and disk ceilings, with a warm pool and scale-to-zero, priority ordering, cancellation of superseded runs, overflow to hosted runners when the pool is saturated, and role-separated tokens (R5.3, separate identities; R8, scaling and queueing).

**DONE WHEN** (requirements.md section 5):

- Every runner shows `ephemeral: true`.
- The load test meets the targets: full suite 60 s or less with warm caches, queue-to-start p95 10 s or less, scale-from-zero to job start 30 s or less, cache hit 95% or more on an unchanged lockfile, each for 5 consecutive runs.
- The mutation test of the queue logic fails when the logic is broken.

**Proof.** Controller logs showing the priority order, `gh api .../actions/runners`, run URLs, a pool load test that reaches its ceiling and returns to zero.

### Starting points

- `scripts/proxmox/ephemeral/homelab-ephemeral-runner.sh` and its unit: one fixed container per instance; the loop rolls the container back to its snapshot `clean`, starts it, mints a JIT configuration through the REST API with an Administration token read from a root-only file on the host, runs one job and repeats. HYPOTHESIS: it does not fit the template-clone design (ADR 0044), which clones a fresh linked clone of the `current` template per job and destroys it; reuse the JIT minting and the backoff, not the rollback loop. Decide its home when the controller layout is chosen.
- `iac/tofu/stacks/guest/` and `scripts/iac/new-guest.sh` ([ADR 0055](../adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md)) already create a flavor-sized linked clone with the guard-compliant firewall, address and VMID from a slot; a controller can reuse the clone, tag and size logic. The stack applies a declared list; a per-job clone needs an adapter that creates and destroys one guest without editing `guests.yml`.
- First spike command (question 4 in the research table below): mint a JIT configuration and list the runners.

```sh
gh api -X POST repos/<owner>/<repository>/actions/runners/generate-jitconfig -f name=spike -F runner_group_id=1 -f 'labels[]=spike' --jq .encoded_jit_config
gh api repos/<owner>/<repository>/actions/runners --jq '.runners[] | {name, ephemeral}'
```

Expected: the first prints a long encoded string (the script above treats HTTP 201 and that field as success); the second lists `spike` with `"ephemeral": true` after a runner has registered with it (HYPOTHESIS: the field is taken from the research notes, not yet observed here).

### Entry gates (before the first runner registers)

1. Fork pull requests are routed to hosted runners in the workflows (the routing expression still selects self-hosted for forks) and the fork-approval setting is on.
2. Runner clones do not keep the default user's passwordless sudo that cloud-init restores at first boot, checked by an R15 row.
3. Root touches probe guests only after checking tag and pool, and runner VMIDs stay outside the template blocks.
4. A per-runner firewall read-back (clones inherit the template firewall).
5. An alert on stale templates or failed builds, and a path to bump the runner pin.
6. The cache writer credential is held only by save steps that run the cache client on artifacts the same run built, checked by a canary on a real runner.
7. The `cache-writer` environment has a branch policy ([limits-and-gaps.md](limits-and-gaps.md), first security gap), and the writer password is rotated after it is set.
8. The controller's identity holds no privilege on the cache container's pool or the cache vnet; closes when `pvesh set` on the cache container returns 403 with the controller token.
9. Runners are JIT and ephemeral before they take any pull-request job.
10. An alarm on cache writes outside writer jobs.
11. A thin-pool headroom guard for runner disks and the cache volume.
12. R15 re-run from a real JIT runner, including the cache-vnet negatives.
13. A host converge that would reboot drains the pool first.
14. The `dotnet-outputs` member check admits only `bin` and `obj` trees (today `^apps/(backend|fixtures)/` also admits `packages.lock.json`, which lets a compromised build job choose the NuGet cache key), or the NuGet save hashes lockfiles from `git show HEAD:<path>` (close-out security review).
15. The tar member guard is a script with a test that feeds it crafted archives (`..`, absolute paths, symlinks, hardlinks); today only its presence before `tar -xf` is tested (close-out security review).
16. A test keeps the runner-class expression in the workflow `env` and the `select-runner` job identical (close-out security review).
17. `wiki-sync` tells an uninitialised wiki apart from an auth or network failure, and checks the commit result (close-out security review).

The close-out security review also recommends deregistering the two offline runners of the retired host now rather than in Phase 6: a pull request can name self-hosted labels in its own workflow file, so registered runners, not the routing expression, are the real exposure.

Open items of the Phase 4 security review (an independent review of the Phase 4 branch; nothing blocked closing Phase 4): the branch policy (gate 7), the cache container's pool (gate 8), guard alerting and cache egress (both Phase 7, see [limits-and-gaps.md](limits-and-gaps.md)).

### Owner steps

| Step | Who |
|---|---|
| Create two fine-grained tokens scoped to the one repository: Administration read and write for the controller (JIT configuration), Administration read for the router job (pool availability) | Repository administrator |
| Set the `cache-writer` environment to selected branches, then rotate the writer password | Repository administrator |
| Set fork pull-request approval to all external contributors | Repository administrator |
| Create the controller's PVE token with a role of its own, separate from the provisioner and backup identities | Operator, reviewed by the technical lead |
| Decide how a stopped pool is detected (D21, VM start policy, is suspended: the lab machines stay running) | Technical lead |

### Controller research

Operator research of 2026-10-07, fetched from the sources named; line numbers refer to the library at tag v0.4.0 and must be re-verified before an ADR relies on them. D10 (build or adopt) and D11 (language) are open; the recommendation is HYPOTHESIS until the spike in the last row.

| Topic | Finding | Source |
|---|---|---|
| Recommendation | Build in-house in Go on the GitHub-published scale-set client library (MIT, public preview, v0.4.0, needs Go 1.25 or newer), with the client behind a port; REST polling of `generate-jitconfig` is the fallback if the preview API breaks | the library's repository at v0.4.0 |
| Protocol | A client built with a personal access token or an app, configured with the repository URL (`client.go:143-158`); runner group lookup (`client.go:360-387`); create a scale set by `POST _apis/runtime/runnerscalesets`, named by the `runs-on` label (`client.go:34-35,393-413`); outbound long-poll `GetMessage`, status 202 meaning no messages (`session_client.go:96-142`); message types JobAvailable, JobAssigned, JobStarted, JobCompleted (`types.go:10-14`) | same |
| Priority and shortest-job-first control point | JobAvailable carries runner request id, repository, owner, job id, workflow ref, display name, workflow run id, event name, request labels and queue time (`types.go:18-46`) before acquisition. Acquisition is explicit: `/<scaleset>/<id>/acquirejobs` (`session_client.go:231`). The stock listener acquires every job (`listener.go:275-289`), so a custom loop that chooses which request ids to acquire is the place to order by class (default branch, pull request, schedule) and by historical duration | same |
| JIT runners | `POST .../generatejitconfig` (`client.go:483-500`); via REST `POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig` needs fine-grained Administration write; listing runners needs Administration read and returns an `ephemeral` boolean | same; GitHub REST documentation |
| Statistics | The scale-set statistics carry totals such as assigned jobs (`types.go:135-143`) | same |
| Adopt instead? | GARM lists no Proxmox provider, scale-set mode needs no webhooks, no priority or shortest-job-first hook was found, version 0.2.0-beta1. Three community Proxmox autoscalers: one on VMs with the guest agent (GPL-3.0, 4 stars, no priority); one that states "Nothing here is usable yet" (Apache-2.0); one without Proxmox support (MIT). None has priority, shortest-job-first or overflow | the projects' documentation |
| Overflow to hosted | No API moves an already queued job to hosted. Patterns: a router job before queueing whose output is `runs-on`; or cancel and re-dispatch after a deadline. A job with no runner fails after 24 hours. Concurrency groups already cancel the older pending run on the same ref | GitHub community discussion 20019; GitHub documentation |
| Rate limits | Personal access token 5,000 requests per hour; secondary limits 100 concurrent requests and 900 points per minute | GitHub documentation |
| OPEN, spike first | (1) Can a scale set be created on a repository owned by a personal account, and which runner group id applies? (2) Does `JobWorkflowRef` carry the ref, or is a REST lookup on the workflow run id needed to classify default branch versus pull request? (3) What happens to a job that is never acquired? (4) Does a JIT runner show `ephemeral: true`? (5) Can one scale set serve several labels on github.com? | requirements row 19 (personal-account limits) |

If the receiving team's repository belongs to an organization, question 1 may not apply (HYPOTHESIS: organization-level runner groups exist; unverified here). Run the spike before choosing build or adopt.

### Design notes (proposals, not decisions)

- Layers: domain (queue, priority classes, shortest-job-first ordering, scaling policy as pure functions), application (use cases: acquire, provision, retire, overflow), infrastructure (GitHub scale-set client, PVE adapter that clones, starts, reads back and destroys). A dependency-rule test mirrors `tests/cache/test_dependency_rule.py`.
- The PVE adapter reuses the existing safety properties: clone only from templates resolved fail closed (ADR 0044), read back the firewall before first start (as the cache start gate does), allocate VMIDs outside the template, probe and flavor-guest blocks, destroy after the job, and never hold a privilege on the cache pool.
- Mutation tests for the queue: break the priority comparison, the shortest-job-first key and the ceiling check, and require a named test to fail for each.
- Measure queue wait, provisioning, checkout, restore, build, test, save and report per run so Phase 6 can compare with the baselines in [results.md](results.md).

## Phase 6: Reusable workflows and cutover

**Goal.** Reusable per-node workflow units bound to one runner class each, per-phase timings in every run summary, optimization from measurements, fork pull requests on hosted runners, labels moved to the new pools, old runners deregistered (R6, reusable workflows; R7, optimization).

**DONE WHEN.** The full suite meets the targets for 5 consecutive runs; no old runner remains. **Proof.** The 5 run URLs and the baseline-versus-after table against the hosted baseline and the old self-hosted baseline in [results.md](results.md).

**State today.** `reusable-sdet-pipeline.yml` is a `workflow_call` workflow with jobs for telemetry, build, test, cache save and report. The split into units such as `dotnet-build`, `dotnet-test`, `angular-test`, `cache-save`, `iac-validate` and `template-build`, callers that only compose with `uses:`, and the unit-to-runner-class table do not exist yet. actionlint cleanliness is part of the pass condition of R6 (reusable workflows).

**Entry.** This phase changes shared CI: run a risk assessment first and record it in the plan (requirements.md section 7.3). Phase 5 entry gates 1 (fork routing) and 9 (JIT ephemeral runners before pull-request jobs) must be closed. The hosted routing of [ADR 0054](../adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md) must be removed in the cutover.

**Backlog.**

| Item | Detail |
|---|---|
| Janitor for runs stuck on offline self-hosted runners | From closed pull request [#49](https://github.com/ugritchaichana/booth-homelab/pull/49), "feat: actions janitor cancels runs stuck on offline self-hosted runners and raises an alert issue" (head `46b3c56`). Replace the retired runner names with the pool labels and keep a dry run on pull requests |

**Owner steps.** The explicit go to deregister the two runners of the retired host (requirements.md section 2.1; the runners API lists them); any GitHub setting beyond secrets (branch protection, visibility, SHA pinning of actions) is the repository administrator's (section 2.2).

## Phase 7: Observability, backups and storage

**Goal.** Metrics for host, pool, queue and cache; alerts; backups to another device with a timed restore; general object storage; drills (requirements.md section 5, Phase 7; a lightweight stack, because RAM is reserved).

**DONE WHEN.** Evidence is stored for the scorecard criteria on backups with a timed restore, observability and alerting, one-command rebuild and disaster-recovery drills ([standard/README.md](../../standard/README.md)). **Proof.** Drill logs with timestamps.

| Item | Source |
|---|---|
| General object storage for artifacts, backups and OpenTofu state: candidate Garage (S3-compatible, maintained). [ADR 0048](../adr/0048-serve-the-build-cache-with-bazel-remote.md) rejected it only as a cache, because it has no LRU eviction; that does not apply to artifacts, backups or state | D85 (general object storage); decide with the backup device |
| Alerts: runner offline over 10 minutes, disk over 85% | requirements.md section 5, Phase 7 |
| Guard alerting: marker and alert on an unreadable policy, ipset content check | [limits-and-gaps.md](limits-and-gaps.md) |
| Cache egress without the public set | [limits-and-gaps.md](limits-and-gaps.md) |
| Alarm on cache writes outside writer jobs (if Phase 5 did not close it) | Phase 5 entry gate 10 |
| Alert on stale templates, failed builds, quarantined cache blobs | Phase 5 entry gate 5; row 65 (cache edge cases) |
| Secrets rotation drills for every secret in [operations.md](operations.md) | operations page |
| TOTP on `root@pam` and a notification target | D60 (TOTP and notifications) |
| Backups to another device, timed restore | Phase 7 text |

**Owner steps.** Provide the backup device; enrol TOTP; choose the notification target.

## Phase 8: Runbook, knowledge and portability

**Goal.** A runbook that rebuilds from zero, a porting guide, a proof on a non-Proxmox host, memory and ADRs (R2, runbook; R10, portability; R18, handoff).

**DONE WHEN.** The timed rebuild is green; the portability proof is green. **Proof.** The rebuild log with start and end timestamps and the proof run URL: a hosted Ubuntu VM converges the same roles and a runner registered from there runs a job green (a Windows-subsystem Debian does not count).

**Starting points.** [build-from-zero.md](build-from-zero.md) is the outline for the timed rebuild; [porting.md](porting.md) is the draft of the porting guide. The rebuild must be done by someone who did not build the platform, and every manual step names its role and exact command.

**Owner steps.** A host for the portability proof; the person who performs the rebuild.

## Order and dependencies

Phase 5 gates, the spike and the build-or-adopt decision first; Phase 6 needs real runners; Phase 7 alerts depend on runner and cache metrics from Phase 5; Phase 8's rebuild is last because it must include everything built before it.
