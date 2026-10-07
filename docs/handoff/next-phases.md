# Next phases (5-8)

Phases 5-8 were planned, not started (requirements.md section 5; the release scope ended after Phase 4, change log 2026-10-07). Each work package below gives the goal, the DONE WHEN clause as written in the requirements, the entry gates, and the owner steps. Before starting any phase, do what the requirements require of every phase: write its blast-radius estimate in four counted dimensions (what breaks and how many, furthest environment reached, time to detect, time to roll back and who) and answer the security pre-flight (section 7.1, 7.2, 7.2a and 7.2b are the model). If time to detect exceeds time to roll back, add signal before starting.

Working rules that carry over (R9, R17, requirements section 8): tests are written red first and mutation-tested where the logic is a queue, scale or key decision; the controller is layered domain, application, infrastructure with a test that fails when the domain imports infrastructure; every finalized decision gets an ADR in the pull request that makes it; pull requests stay at 30 files or fewer; never narrow a check to go faster.

## Effort

| Item | Value | Status |
|---|---|---|
| Phase 4, one operator (an AI agent) on the reference machine | About 3.5 hours | Reported in the requirements change log, 2026-10-07; not instrumented |
| Phases 5-8 | The operator of the reference work estimated 12-20 hours | HYPOTHESIS: an estimate by that operator, for that operator, not measured |
| Phases 5-8 for the receiving team | Unknown | Measure the first work package of Phase 5 and re-plan from it |

The criteria numbers quoted below (1.3, 1.5, 3.1, 3.2, 3.4, 3.5) refer to the 100-point scorecard of the original project (R14), whose document is not part of this repository tree; treat them as labels for "evidence stored for X" and map them to the receiving team's own acceptance criteria.

## Phase 5: Runner pool controller

**Goal.** A JIT ephemeral runner per job, scaling with queue depth inside host CPU, RAM and disk ceilings, with a warm pool and scale-to-zero, priority ordering, cancellation of superseded runs, overflow to hosted runners when the pool is saturated or unavailable, and role-separated tokens (R5.3, R8, D3, D14).

**DONE WHEN** (requirements.md section 5):

- Every runner shows `ephemeral: true`.
- The load test meets Q7: full suite 60 s or less with warm caches, queue-to-start p95 10 s or less, scale-from-zero to job start 30 s or less, cache hit 95% or more on an unchanged lockfile, each for 5 consecutive runs.
- The mutation test of the queue logic fails when the logic is broken.

**Proof.** Controller logs showing the priority order, `gh api .../actions/runners`, run URLs, a pool load test that reaches its ceiling and returns to zero.

### Entry gates (before the first runner registers)

From requirements.md section 5:

1. Fork pull requests are routed to hosted runners in the workflows (the current expression still selects self-hosted for forks, row 27, D17) and the fork-approval setting is on.
2. Runner clones do not keep the default user's passwordless sudo that cloud-init restores at first boot, checked by an R15 row (row 59).
3. Root touches probe guests only after checking tag and pool, and runner VMIDs stay outside the template blocks.
4. A per-runner firewall read-back (clones inherit the template firewall, row 58).
5. An alert on stale templates or failed builds, and a path to bump the runner pin.
6. The cache writer credential is held only by save steps that run the cache client on artifacts the same run built, checked by a canary (the wiring exists, row 70; the canary on a real runner does not).
7. The `cache-writer` environment has a branch policy (repository administrator), and the writer password is rotated after it is set.
8. The controller's identity holds no privilege on the cache container's pool or the cache vnet.
9. Runners are JIT and ephemeral before they take any pull-request job.
10. An alarm on cache writes outside writer jobs.
11. A thin-pool headroom guard for runner disks and the cache volume.
12. R15 re-run from a real JIT runner, including the cache-vnet negatives.
13. A host converge that would reboot drains the pool first.

From the Phase 4 security review (a review by an independent security role of the Phase 4 branch; verdict: nothing blocks closing Phase 4, and four items become blocking at Phase 5 entry):

| Review item | Disposition |
|---|---|
| The writer password shared a job environment with install scripts, and the save job packed whatever was in the workspace | Fixed in Phase 4: build and test jobs upload artifacts, the save job runs only the client with the password at step level (row 70). Gate 6 proves it on a real runner |
| The writer gate is the environment, which had no branch policy; a same-repository branch can name it | Open: gate 7 |
| The provisioner token reaches the cache container because it shares pool `homelab`; fix: a separate pool without a provisioner ACL, an operator-scoped token for the cache stack, no cache-vnet `SDN.Use` for the provisioner | Open: gate 8; closes when `pvesh set` on the cache container returns 403 with the controller token |
| Restore extracted any path and decompression was unbounded | Fixed in Phase 4 (row 70) |
| The evidence checker trusted its own test vectors | Fixed in Phase 4 (row 70) |
| The guard exits 4 on an unreadable policy with no marker or alert; the ipset contents are not checked | Open: Phase 7 |
| The start gate checked one NIC only | Fixed in Phase 4 (row 70) |
| The cache container keeps public egress; a compromised service could call out | Open: Phase 7 |
| R15 rows for runner to cache gateway ports and a closed cache port were missing | Fixed in Phase 4 (row 66); gate 12 repeats them from a real runner |
| Nine systemd sandbox directives missing from the cache unit | Fixed in Phase 4 (row 70) |

### Owner steps

| Step | Who | Source |
|---|---|---|
| Create two fine-grained tokens scoped to the one repository: Administration read and write for the controller (JIT configuration), Administration read for the router job (pool availability) | Repository administrator | D14, D15; row 20 |
| Set the `cache-writer` environment to selected branches (default branch), then rotate the writer password | Repository administrator | ADR 0050 |
| Set fork pull-request approval to all external contributors | Repository administrator | row 27 |
| Create the controller's PVE token with a role of its own, separate from the provisioner and backup identities | Operator, reviewed by the technical lead | R5.3 |
| Decide how a stopped pool is detected (the reference VM started on demand, D21, D25) | Technical lead | D25 |

### Controller research

Operator research of 2026-10-07, fetched from the sources named; line numbers refer to the library at tag v0.4.0 and must be re-verified before an ADR relies on them. D10 (build or adopt) and D11 (language) are open; the recommendation below is HYPOTHESIS until the spike in the last row.

| Topic | Finding | Source |
|---|---|---|
| Recommendation | Build in-house in Go on the GitHub-published scale-set client library (MIT, public preview, v0.4.0, needs Go 1.25 or newer), with the client behind a port; REST polling of `generate-jitconfig` is the fallback if the preview API breaks | the library's repository at v0.4.0 |
| Protocol | A client built with a personal access token or an app, configured with the repository URL (`client.go:143-158`); runner group lookup (`client.go:360-387`); create a scale set by `POST _apis/runtime/runnerscalesets`, named by the `runs-on` label (`client.go:34-35,393-413`); outbound long-poll `GetMessage`, status 202 meaning no messages (`session_client.go:96-142`); message types JobAvailable, JobAssigned, JobStarted, JobCompleted (`types.go:10-14`) | same |
| Priority and shortest-job-first control point | JobAvailable carries runner request id, repository, owner, job id, workflow ref, display name, workflow run id, event name, request labels and queue time (`types.go:18-46`) before acquisition. Acquisition is explicit: `/<scaleset>/<id>/acquirejobs` (`session_client.go:231`). The stock listener acquires every job (`listener.go:275-289`), so a custom loop that chooses which request ids to acquire is the place to order by class (default branch, pull request, schedule) and by historical duration | same |
| JIT runners | `POST .../generatejitconfig` (`client.go:483-500`); via REST `POST /repos/{owner}/{repo}/actions/runners/generate-jitconfig` needs fine-grained Administration write; listing runners needs Administration read and returns an `ephemeral` boolean | same; GitHub REST documentation |
| Statistics | The scale-set statistics carry totals such as assigned jobs (`types.go:135-143`) | same |
| Adopt instead? | GARM lists no Proxmox provider, scale-set mode needs no webhooks, no priority or shortest-job-first hook was found, version 0.2.0-beta1. Three community Proxmox autoscalers: one on VMs with the guest agent (GPL-3.0, 4 stars, no priority); one that states "Nothing here is usable yet" and claims personal-account support with runner group "default" (Apache-2.0); one without Proxmox support (MIT). None has priority, shortest-job-first or overflow | the projects' documentation |
| Overflow to hosted | No API moves an already queued job to hosted. Patterns: a router job before queueing whose output is `runs-on`; or cancel and re-dispatch after a deadline. A job with no runner fails after 24 hours. Concurrency groups already cancel the older pending run on the same ref | GitHub community discussion 20019; GitHub documentation |
| Rate limits | Personal access token 5,000 requests per hour; secondary limits 100 concurrent requests and 900 points per minute | GitHub documentation |
| OPEN, spike first | (1) Can a scale set be created on a repository owned by a personal account, and which runner group id applies? (2) Does `JobWorkflowRef` carry the ref, or is a REST lookup on the workflow run id needed to classify default branch versus pull request? (3) What happens to a job that is never acquired? (4) Does a JIT runner show `ephemeral: true`? (5) Can one scale set serve several labels on github.com? | requirements row 19 (personal-account limits) |

If the receiving team's repository belongs to an organization, question 1 may not apply (HYPOTHESIS: organization-level runner groups exist; unverified here). Run the spike before choosing build or adopt.

### Design notes (proposals, not decisions)

- Layers: domain (queue, priority classes, shortest-job-first ordering, scaling policy as pure functions), application (use cases: acquire, provision, retire, overflow), infrastructure (GitHub scale-set client, PVE adapter that clones, starts, reads back and destroys). A dependency-rule test mirrors `tests/cache/test_dependency_rule.py`.
- The PVE adapter must reuse the existing safety properties: clone only from templates resolved fail closed (ADR 0044), read back the firewall before first start (as the cache start gate does), allocate VMIDs outside the template and probe blocks, destroy after the job, and never hold a privilege on the cache pool.
- Mutation tests for the queue: break the priority comparison, the shortest-job-first key and the ceiling check, and require a named test to fail for each.
- Measure queue wait, provisioning, checkout, restore, build, test, save and report per run (R7) so Phase 6 can compare with the baselines in [results.md](results.md).

## Phase 6: Reusable workflows and cutover

**Goal.** Reusable per-node workflow units bound to one runner class each, per-phase timings in every run summary, optimization from measurements, fork pull requests on hosted runners, labels moved to the new pools, old runners deregistered (R6, R7, D17).

**DONE WHEN.** The full suite meets Q7 for 5 consecutive runs; no old runner remains. **Proof.** The 5 run URLs and the baseline-versus-after table against runs 37355482969 (71 s hosted) and 37341728563 (174 s old self-hosted).

**State today.** `reusable-sdet-pipeline.yml` is a `workflow_call` workflow with jobs for telemetry, build, test, cache save and report; the R6 split into units such as `dotnet-build`, `dotnet-test`, `angular-test`, `cache-save`, `iac-validate` and `template-build`, callers that only compose with `uses:`, and the "unit to runner class" table do not exist yet (R6). actionlint cleanliness is part of R6's pass condition.

**Entry.** This phase changes shared CI: run a risk assessment first and record the result in the plan (requirements.md section 7.3, last line). Phase 5 entry gates 1 (fork routing) and 9 (JIT ephemeral runners before pull-request jobs) must be closed.

**Owner steps.** The explicit go to deregister the two runners of the retired host (section 2.1 row 11; the runners are listed by the runners API); any GitHub setting beyond secrets (branch protection, visibility, SHA pinning of actions) is the repository administrator's (section 2.2).

## Phase 7: Observability and resilience

**Goal.** Metrics for host, pool, queue and cache; alerts; backups to another device with a timed restore; drills (requirements.md section 5, Phase 7; Q14: a lightweight stack, because RAM is reserved).

**DONE WHEN.** Evidence for criteria 3.1, 3.2, 3.4 and 3.5 is stored. **Proof.** Drill logs with timestamps.

Work packages that the earlier phases already named:

| Item | Source |
|---|---|
| Alerts: runner offline over 10 minutes, disk over 85% | requirements.md section 5, Phase 7 |
| Guard alerting: marker and alert on an unreadable policy, ipset content check | Phase 4 security review; [limits-and-gaps.md](limits-and-gaps.md) |
| Cache egress without the public set | same |
| Alarm on cache writes outside writer jobs (if not closed by Phase 5) | Phase 5 entry gate 10 |
| Alert on stale templates, failed builds, quarantined cache blobs | Phase 5 entry gate 5; row 65 |
| Secrets rotation drills for every secret in [operations.md](operations.md) | operations gap |
| TOTP on `root@pam` and a notification target | D60 |
| Backups to another device, timed restore | Phase 7 text |

**Owner steps.** Provide the backup device; enrol TOTP; choose the notification target.

## Phase 8: Runbook, knowledge and portability

**Goal.** A runbook that rebuilds from zero, a porting guide, a proof on a non-Proxmox host, memory and ADRs (R2, R10, R18).

**DONE WHEN.** The timed rebuild is green; the portability proof is green. **Proof.** The rebuild log with start and end timestamps and the proof run URL: a hosted Ubuntu VM converges the same roles and a runner registered from there runs a job green (a Windows-subsystem Debian does not count, R10).

**Starting points.** [build-from-zero.md](build-from-zero.md) is the outline for the timed rebuild; [porting.md](porting.md) is the draft of the porting guide. The rebuild must be done by someone who did not build the platform (R18); every manual step names its role and exact command (R18).

**Owner steps.** A host for the portability proof; the person who performs the rebuild.

## Order and dependencies

Phase 5 gates, spike and design decision (D10, D11) first; Phase 6 needs real runners; Phase 7 alerts depend on runner and cache metrics from Phase 5; Phase 8's rebuild is last because it must include everything built before it.
