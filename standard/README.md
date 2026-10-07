# Homelab Engineering Standard — the 100-point target

**Applies to:** the repository `OWNER/REPO` and any homelab built from it.
**Frame:** a baseline another team could clone and depend on. **100 = every criterion shown working, sustained.**
**Version:** 1.0 · 2026-10-05 · Author: maintainers.

---

## 1. How the score works

- 25 criteria in 5 axes. Each criterion scores **0, 1 or 2** exactly as defined under it.
- Axis score = sum of its five criteria (0–10). **Composite = mean of the five axis scores × 10.**
  One criterion point = 2 composite points.
- Bands: **0–49 REJECTED · 50–79 APPROVED WITH CONDITIONS · 80–100 APPROVED.**
- **100 requires all three:** every criterion at 2 with fresh evidence; no blocking condition open (section 2.4);
  the weekly scorecard at 100 for **four consecutive weeks**. A single good day is not 100.

## 2. Conditions that apply to every criterion

1. **Evidence rule.** A criterion counts only with a stored evidence record (template in section 5): what was run,
   its raw output, the date, the commit SHA, who or what ran it.
   - Runtime behaviour (does the firewall block, does the lock refuse, does the restore work) needs a measurement.
     Reading the code is not evidence that a control works.
   - Properties of the code itself (layout, test oracles, configuration values) are evidenced by the code at a
     pinned SHA.
2. **Freshness.** Evidence expires after 90 days unless the criterion says otherwise, and immediately when a file
   the criterion covers changes. Expired evidence scores 0 until re-measured.
3. **Where to measure.** Infrastructure criteria on the live system, or on a disposable replica built by the same
   IaC. Code criteria in CI.
4. **Blocking conditions.** While any is open, the composite is capped at 49:
   - **Exposed credential** — a secret in the tree or the history of a repository others can read.
   - **Untrusted execution** — code from outside the trusted set can run on persistent infrastructure.
   - **False green** — a required check can pass without running what it claims to test.
   - **Unsupported software** — any component past its vendor's end of security support. A component within
     30 days of its end date with no dated upgrade plan in the repo counts as unsupported.
5. **Regression ratchet.** The scorecard job fails when any criterion drops below its last recorded score. The
   drop is fixed, or acknowledged in a dated note in the evidence ledger.
6. **Partial credit names the gap.** An evidence record that scores 1 states which requirement is missing.
7. **Supported-version check** (feeds condition 4): `curl -s https://endoflife.date/api/<product>.json` for
   `proxmox-ve`, `nodejs`, `dotnet`, `alpine-linux`, compared with the versions the repo pins.

---

## 3. The 25 criteria

### Axis 1 — Isolation and blast radius

#### 1.1 Untrusted code cannot reach persistent infrastructure
- **Must:** (a) the repository is private, **or** every self-hosted runner is ephemeral — one job per instance,
  then destroyed or reset to a clean image; (b) no job started by `pull_request_target` runs on a self-hosted
  label; (c) if the repository is public, fork pull-request workflows need approval for all external contributors.
- **Measure:**
  ```
  gh api repos/OWNER/REPO --jq .visibility
  grep -rn 'generate-jitconfig' scripts/proxmox/ephemeral        # JIT registration, one job per runner
  grep -l pull_request_target .github/workflows/*.yml | xargs grep -n 'runs-on'
  gh api repos/OWNER/REPO/actions/permissions/fork-pr-contributor-approval --jq .approval_policy
  ```
- **Score:** 2 = a, b, c · 1 = a met, b or c not · 0 = a not met.

#### 1.2 Every job starts clean
- **Must:** (a) each job runs on a fresh instance or one reset to a known image; (b) no long-lived credentials
  stored on the runner — cache, registry and API credentials are injected per job (secrets or OIDC) and gone at job
  end; (c) temporary files live under `$RUNNER_TEMP` or come from `mktemp`, never at fixed shared paths.
- **Measure:** a canary pair — job A writes `$HOME/.canary` and `/tmp/canary`; job B on the same label must find
  neither. In a fresh job, `env | grep -iE 'cache.*(pass|token)'` and `ls ~/.docker ~/.config` show no stored credentials.
  `grep -rnE '"/tmp/[A-Za-z]|=/tmp/[A-Za-z]' scripts/ .github/` returns nothing.
- **Score:** 2 = a, b, c · 1 = two of three · 0 = otherwise.

#### 1.3 Host and neighbouring runners are unreachable from jobs, and stay that way
- **Must:** (a) the runner subnet cannot reach any host management port (SSH, hypervisor API and UI); (b)
  runner-to-runner traffic is blocked at L3 and by bridge port isolation; (c) IPv6 is filtered with equivalent
  rules or disabled on runner interfaces; (d) a, b and c survive a container restart and a host reboot with no
  manual step (hookscript, systemd unit, or the hypervisor's own firewall configuration).
- **Measure:** connectivity checks from inside each runner container — **every one must fail**:
  ```
  nc -z -w2 HOST_GATEWAY 22
  nc -z -w2 HOST_GATEWAY 8006
  nc -z -w2 OTHER_RUNNER_IP OPEN_PORT_ON_IT
  ping -6 -c1 -w2 OTHER_RUNNER_LINK_LOCAL%eth0
  ```
  Then restart the container and reboot the host, and run the checks again. On the host,
  `bridge -d link show | grep -c 'isolated on'` equals the number of runner ports.
  `tests/isolation/r15-probe.sh` produces the probe output; published runs are listed in section 8.
- **Score:** 2 = a–d · 1 = a and b pass (IPv4), c or d missing · 0 = otherwise.

#### 1.4 Least privilege
- **Must:** (a) the job user cannot become root without a password; if Docker is needed, rootless Docker or a
  scoped socket proxy, not the `docker` group; (b) the build cache accepts anonymous reads and one writer credential
  (ADR 0050), and no CI credential has wider scope; (c) write credentials reach only jobs on trusted refs (a GitHub
  Environment secret whose deployment-branch policy allows only the default branch); (d) automation tokens on the
  hypervisor are privilege-separated with only the roles and paths they need.
- **Measure:** as the runner user, `sudo -n true; echo $?` is non-zero. An anonymous write to the cache returns 401 and an anonymous read of a stored blob returns 200
  ([cache API run](../docs/evidence/phase4/cache-api.txt)).
  `gh api repos/OWNER/REPO/environments/ENV --jq .deployment_branch_policy` limits the environment to the default
  branch. On the host, `pveum acl list` shows only scoped roles for the automation user.
- **Score:** 2 = a–d · 1 = three of four · 0 = two or fewer.

#### 1.5 Egress control that works
- **Must:** (a) runner egress is allowlisted by domain (forward proxy) or by provider-published ranges that refresh
  automatically; (b) the allowlist covers every domain GitHub documents for self-hosted runners — essential
  operations (`github.com`, `api.github.com`, `*.actions.githubusercontent.com`), action downloads
  (`codeload.github.com`), artifacts, caches and logs (`results-receiver.actions.githubusercontent.com`,
  `*.blob.core.windows.net`), runner updates (`objects.githubusercontent.com` and siblings) — plus the package
  registries in use; (c) denied requests are logged with their destination; (d) runners stay online and jobs
  succeed under the policy.
- **Measure:** runner status sampled hourly for 7 days
  (`gh api repos/OWNER/REPO/actions/runners --jq '.runners[]|"\(.name) \(.status)"'`) is always `online`. One job
  doing checkout, package restore and `upload-artifact` is green. From a runner, `curl -sS -m5 https://example.com`
  fails and appears in the proxy or firewall log.
- **Score:** 2 = a–d · 1 = b and d pass, but logging or automatic refresh is missing · 0 = runners cannot work
  under the policy, or egress is unrestricted.

### Axis 2 — Infrastructure as code and day-2 operations

#### 2.1 IaC is the single source of truth
- **Must:** (a) every live resource — containers, bridges, firewall, services, cache users and policies — is
  created from the repo's IaC; (b) imperative provisioning scripts are removed or reduced to thin wrappers that
  call the IaC; (c) drift detection runs on a schedule and reports differences.
- **Measure:** `tofu plan -detailed-exitcode` exits 0 against the live system. A second
  `ansible-playbook playbooks/site.yml --check --diff` reports `changed=0`. The scheduled drift workflow is green
  for 4 consecutive weeks. `ls scripts/proxmox` lists only scripts documented as the installer or as wrappers.
- **Score:** 2 = a, b, c · 1 = a shown (plan and check clean) but b or c missing · 0 = otherwise.

#### 2.2 Remote state with proven locking
- **Must:** (a) remote state backend in use (state migrated, object present); (b) locking enabled and proven — a
  concurrent run is refused; (c) the state bucket is versioned and readable only by the operator's credential,
  because state holds sensitive values.
- **Measure:**
  ```
  tofu -chdir=iac/tofu/stacks/proxmox-host plan -lock-timeout=0s &   # holds the lock
  tofu -chdir=iac/tofu/stacks/proxmox-host plan -lock-timeout=0s     # must fail with a state-lock error
  # state bucket versioning enabled, and unreadable without the operator's credential (storage provider's own tool)
  ```
  S3-native locking (`use_lockfile = true`) needs OpenTofu ≥ 1.10; raise `required_version` in
  `iac/tofu/stacks/*/versions.tf`. ADR 0051 keeps state local, so this criterion stays at 0 until that decision changes.
- **Score:** 2 = a, b, c · 1 = a shown, b or c missing · 0 = otherwise.

#### 2.3 Idempotency is proven by recorded runs
- **Must:** (a) a second consecutive `ansible-playbook playbooks/site.yml` reports `changed=0` on every host; (b)
  `tofu apply` followed by `tofu plan -detailed-exitcode` exits 0; (c) both recorded by CI or a scheduled job, with
  output stored.
- **Score:** 2 = a, b, c · 1 = a or b recorded · 0 = neither recorded.

#### 2.4 Secrets lifecycle
- **Must:** (a) no secret in the working tree or the full history; (b) secrets live in a manager (SOPS + age, Vault
  or GitHub secrets), are injected at runtime, and scripts fail when one is missing (no defaults); (c) secret
  scanning blocks reintroduction (pre-commit hook and a CI job on pull requests); (d) the rotation runbook was
  exercised within the last 90 days.
- **Measure:**
  ```
  gitleaks detect --log-opts="--all"                                              # 0 findings
  grep -rnE 'getenv\("[A-Z_]*(PASS|SECRET|TOKEN|KEY)[A-Z_]*", *"[^"]+"' scripts/  # nothing
  ```
  CI workflow contains the scan step. Rotation log entry dated within 90 days.
- **Score:** 2 = a–d · 1 = b met and tree clean, with history, scanning or rotation still missing · 0 = otherwise.

#### 2.5 IaC CI goes beyond syntax
- **Must:** on every pull request touching `iac/`: (a) `tofu fmt -check`, `tofu validate`, `tflint`; (b) a
  `tofu plan` against a test target (or the live host, read-only) published on the PR; (c)
  `ansible-lint --profile production` and a converge-plus-idempotence test on a disposable target (for example
  Molecule with a container); (d) tool versions pinned.
- **Measure:** the workflow contains these steps, and the last 5 IaC pull requests show them green.
- **Score:** 2 = a–d · 1 = a plus `ansible-lint`, without plan or converge · 0 = syntax checks only.

### Axis 3 — Resilience and disaster recovery

#### 3.1 Backups with a timed restore
- **Must:** (a) scheduled backups of every stateful item — container and VM disks and configs, `/etc/pve`,
  tofu state, any cache data that cannot be regenerated; (b) stored on a different physical device, with
  retention defined; (c) a restore test into a scratch target at least every 30 days, with RTO and RPO measured
  and logged; (d) a failed backup raises an alert.
- **Measure:** `pvesh get /cluster/backup` (or the backup server's job list) shows the schedule. The newest backup
  is younger than the schedule interval. A restore log with start and end timestamps is at most 30 days old.
  A deliberately failed backup produces an alert.
- **Score:** 2 = a–d · 1 = a and b, with no restore test in 30 days · 0 = otherwise.

#### 3.2 Observability and alerting
- **Must:** (a) metrics for host CPU, memory, disk and temperature, per-container usage, runner online status,
  job queue time, job duration and cache hit ratio; (b) alerts for a runner offline more than 10 minutes, disk
  above 85 %, a failed backup and an unreachable host, delivered to a channel the operator watches; (c)
  time-to-detect measured — a deliberate fault (stop a runner service) produces an alert, and the delay is
  logged.
- **Score:** 2 = a, b, c · 1 = a without tested alerting · 0 = otherwise.

#### 3.3 CI survives losing the host
- **Must:** (a) with the host down, CI for every label still completes **without human action**, through a second
  host or an automatic availability-based fallback to hosted runners; (b) losing the cache degrades to a cold
  build, not a failure; (c) backups and state are not on the host's own disk (see 3.1).
- **Measure:** drill — power off the host, push a commit with a code change, and the full pipeline completes green
  within the documented time with no manual step. Log the timestamps.
- **Score:** 2 = drill passes with no human action · 1 = drill passes with a documented manual switch taking
  15 minutes or less · 0 = otherwise.
- **Note:** reachable on one machine. An availability-based selector needs read access to the runner list; check
  what the workflow token can read before choosing that design.

#### 3.4 One-command rebuild, timed
- **Must:** (a) one documented command takes a freshly installed hypervisor (or bare metal) to a working CI stack —
  runners online, cache up, first pipeline green; (b) the rebuild was run end to end within the last 90 days,
  timed, with the log stored; (c) the duration is within the target the documentation states. A time claim that
  was never measured is removed.
- **Score:** 2 = a, b, c · 1 = an end-to-end rebuild was logged but needed several steps or ran over target ·
  0 = never logged.

#### 3.5 Disaster-recovery drills on record
- **Must:** (a) a drill at least every 90 days covering each of: host loss (3.3), cache corruption, state loss
  (restore tofu state from versioning or backup), credential rotation (2.4 d); (b) each drill logged with
  scenario, steps, timestamps, outcome and follow-ups.
- **Score:** 2 = all four scenarios within 90 days · 1 = at least one within 90 days · 0 = none.

### Axis 4 — Ergonomics and golden path

#### 4.1 A new engineer brings it up from the README
- **Must:** (a) the README states prerequisites, one bring-up path and a target time; (b) someone follows only the
  README, reaches a green pipeline within the target time, and every deviation is fed back into the README.
- **Score:** 2 = b done by a person new to the repo within the last 180 days · 1 = b done by the maintainer on a
  fresh machine, or by an agent with no prior context, using only the README, logged · 0 = untested.

#### 4.2 Documentation is accurate
- **Must:** (a) every numeric or superlative claim — throughput, timings, versions, "zero-trust", compliance labels,
  release numbers — links to evidence (run, log, evidence record) or is removed; (b) a CI check fails on a claim
  that has no evidence link (for example, a claims register that every such claim must appear in).
- **Measure:**
  ```
  grep -rnE '[0-9]+(\.[0-9]+)? ?(MiB/s|GB/s|ms|min|%)|v[0-9]+\.[0-9]+\.[0-9]+|Zero-Trust|Enterprise|SOC ?2|ISO.?27001' \
    README.md wiki/ AGENTS.md
  ```
  Every hit links to evidence or is removed.
- **Score:** 2 = no unbacked claim and the CI check in place · 1 = no unbacked claim, no CI check · 0 = any
  unbacked claim.

#### 4.3 Conventional layout and templates
- **Must:** (a) a standard layout (`apps/`, `iac/`, `scripts/`, `docs/` or `wiki/`, `.github/`); (b) issue templates,
  a pull-request template with a Definition-of-Done checklist, and `CODEOWNERS`.
- **Score:** 2 = a and b · 1 = one of them · 0 = neither.

#### 4.4 Independent review is enforced
- **Must:** (a) branch protection requires an approving review from someone other than the author, with
  `enforce_admins: true`; (b) required status checks include the test gate and the scorecard job; (c) no direct
  pushes to the default branch in the last 30 days.
- **Measure:**
  ```
  gh api repos/OWNER/REPO/branches/master/protection \
    --jq '{admins: .enforce_admins.enabled, approvals: .required_pull_request_reviews.required_approving_review_count, checks: .required_status_checks.contexts}'
  ```
- **Score:** 2 = a, b, c with a human second reviewer · 1 = single-maintainer form: `enforce_admins: true`,
  pull-request-only workflow, required approvals set to 0, plus required status checks that include an independent
  automated review · 0 = otherwise.

#### 4.5 Changes carry evidence
- **Must:** (a) every change lands through a pull request; (b) each pull request or commit body includes the
  Definition-of-Done evidence (command and output, or a run link) for what it claims; (c) conventional commit
  messages.
- **Measure:** for the last 30 days, merged pull requests (`gh pr list --state merged`) against commits on the
  default branch (`git rev-list --count --since="30 days ago" origin/master`); sample 10 for evidence blocks.
- **Score:** 2 = a, b, c for at least 90 % of changes · 1 = at least 50 % · 0 = below 50 %.

### Axis 5 — Test-rig determinism

#### 5.1 Test selection is fail-closed and verified
- **Must:** (a) an unmappable non-documentation change, or a shared build-config change, selects the full suite;
  (b) push events diff the whole pushed range (`github.event.before`, guarded for new branches); (c) the selector's
  harness runs in CI on every selector change, against the same script CI executes; (d) a mutation check —
  deleting the fail-closed block makes the harness fail — is recorded for each selector change.
- **Score:** 2 = a–d · 1 = a and b each shown by a recorded run, c or d missing · 0 = otherwise.

#### 5.2 Every advertised path has actually run
- **Must:** (a) each alternative path the docs or workflows advertise — hosted fallback, cache-miss path,
  cache-endpoint-unreachable path — has a recorded green run within 90 days; (b) a scheduled job exercises them
  (for example a monthly dispatch with `force_ubuntu_runner: true`).
- **Score:** 2 = a and b · 1 = a only · 0 = any advertised path never ran.

#### 5.3 Pipeline telemetry is correct
- **Must:** (a) every reported metric (cache hit, durations) matches the underlying log in every run, and durations
  are reported for failed runs too; (b) a CI assertion compares the summary with the step's own log marker — if the
  log says `[CACHE HIT]`, the summary must say `true`.
- **Score:** 2 = a and b · 1 = a verified on at least 5 consecutive runs, b missing · 0 = any mismatch.

#### 5.4 Test oracles pin behaviour at the boundaries
- **Must:** (a) expected values come from the domain — hand-computed or exact integer arithmetic — never from the
  code under test; (b) boundary fixtures for every rounding, clamp and limit (half-cent rounding mode, discount
  larger than the subtotal, negative input); (c) a rule implemented in more than one stack uses one shared fixture
  table that both stacks run.
- **Score:** 2 = a, b, c · 1 = a only · 0 = otherwise.

#### 5.5 Flakiness measured, test resources bounded
- **Must:** (a) each suite has a recorded repeat run (for example 20 consecutive runs) with 0 flaky failures within
  90 days; (b) test resource limits configured and sized to the runner — Jest `maxWorkers` and
  `workerIdleMemoryLimit`, .NET test parallelism; (c) a flaky-test policy: a flaky test is quarantined with a
  tracking issue within 24 hours.
- **Score:** 2 = a, b, c · 1 = a or b · 0 = otherwise.

---

## 4. Limits for one host and one maintainer

- **Ceiling: 96.** 4.1 caps at 1 without someone new to the repo, and 4.4 caps at 1 without a second human
  reviewer. Every other criterion is reachable on one machine by one person.
- 3.3 does not need a second machine: an automatic, availability-based fallback that a drill proves meets it.
- The last 4 points need a second person — a friend or teammate who runs the README once (4.1) and reviews pull
  requests (4.4).

## 5. Measurement system — make the standard measure itself

**Layout in the repo:**
```
standard/README.md                    this document
standard/evidence/<criterion>/<date>.md   one record per measurement
standard/checks/<criterion>.sh        automated checks
docs/evidence/phase<N>/               sanitized runs of the platform, cited from records (section 8)
.github/workflows/standard-scorecard.yml  weekly + on pull requests: runs the checks, reads the ledger,
                                      applies freshness and the ratchet, writes the scorecard to the job summary
```

**Evidence record template:**
```markdown
# <criterion number> — <criterion name>
- Date / Commit: 2026-MM-DD / <sha>
- Measured by: <person, or job run link>
- Procedure: <exact commands or drill steps>
- Raw output: <fenced block, unedited>
- Result: score <0|1|2> — met: <requirements> · missing: <requirements>
- Expires: <date> or "on change to <paths>"
```

**How each criterion is measured:**

| Measured by | Criteria |
|---|---|
| CI, every pull request and weekly | 1.1 untrusted code cannot reach persistent infrastructure; 1.2 every job starts clean (temp-path scan); 2.4 secrets lifecycle (scanner); 2.5 IaC CI beyond syntax; 4.2 documentation is accurate; 4.3 conventional layout and templates; 4.4 independent review is enforced; 4.5 changes carry evidence; 5.1 test selection is fail-closed; 5.3 pipeline telemetry; 5.5 flakiness and test resources (configuration) |
| Scheduled job on the host | 1.3 host and neighbouring runners unreachable; 1.5 egress control; 2.1 IaC is the single source of truth; 2.2 remote state with locking; 2.3 idempotency proven by recorded runs; 3.1 backups with a timed restore (backup age); 3.2 observability and alerting (alert test) |
| Drill or one-off, logged by hand | 1.2 every job starts clean (canary pair); 2.4 secrets lifecycle (rotation); 3.1 backups with a timed restore (restore); 3.3 CI survives losing the host; 3.4 one-command rebuild; 3.5 disaster-recovery drills; 4.1 a new engineer brings it up from the README; 5.2 every advertised path has run; 5.5 flakiness measured (repeat runs) |

**Tools already in the repo that can produce evidence:** `tests/isolation/r15-probe.sh` and
`scripts/hyperv/Test-R15Controls.ps1` (1.3, host and neighbouring runners unreachable), `scripts/evidence/publish.py` (stores sanitized runs under
`docs/evidence/`), `tests/verify-affected-graph.sh` (5.1, test selection is fail-closed).

---

## 6. Recording evidence

- **Where.** `standard/evidence/<criterion>/<YYYY-MM-DD>.md`, one file per measurement. The newest dated file is the
  current record. Never edit an old record: add a new dated one.
- **Template.** The one in section 5, unchanged. The scorecard reads three lines of it:
  `- Date / Commit: <date> / <full commit sha>`, `- Result: score <0|1|2> ...` and
  `- Expires: <date> or on change to <paths>`. The paths that actually expire a record are the `covered_paths` column
  of `standard/criteria.tsv`; the `Expires` line must name the same paths.
- **Raw output** is pasted unedited, one block per command, with the exact command above it so it can be re-run and
  diffed. Credential values are masked before pasting; secret scans record counts only. Stripping ANSI colour codes
  from a job log is allowed when the stripping command is part of the recorded command.
- **Measured by** is a job run link, or "maintainers, read at <sha>" for a property of the code.
- **A score of 1 names the missing requirement** (section 2, condition 6).
- **Acknowledging a drop.** `standard/evidence/<criterion>/<YYYY-MM-DD>-ack.md`, dated on or after the record it
  covers, stating why the drop is accepted. Without it the ratchet fails.

### Evidence-link convention for 4.2

A line hit by the 4.2 grep is backed when the same line holds a Markdown link to one of:

1. `https://github.com/OWNER/REPO/actions/runs/<digits>`, optionally followed by `/job/<digits>` or
   `/attempts/<n>`;
2. a file under `standard/evidence/` (a relative path, or a repository blob or tree URL that ends in such a path);
   the file must exist;
3. `https://github.com/OWNER/REPO/blob/<40-hex sha>/<path>#L<n>`; where a git history is
   available, the commit and the path must exist;
4. a file under `docs/evidence/phase<N>/` (a relative path, or a repository blob or tree URL that ends in such a
   path); the file must exist.

Anything else is unbacked, including badge images and release links. `standard/checks/4.2.sh` enforces this and
fails the `doc-claims` job while any hit is unbacked; that failing check is criterion 4.2 requirement (b).

---

## 7. How the scorecard computes

`.github/workflows/standard-scorecard.yml` runs on pull requests, on pushes to the default branch, every Monday and
on demand. Job `scorecard` runs the scorer's unit tests and then `standard/scorecard.py`, which writes a Markdown
table to the job summary. Job `doc-claims` runs `standard/checks/4.2.sh` alone.

**Inputs.** `standard/criteria.tsv` has one tab-separated row per criterion: `id`, `axis`, `name`, `measured_by`
(`ci`, `host` or `drill`, following the table in section 5; 1.4 and 5.4 are not in that table and are placed by where
their evidence comes from; `retired` marks a criterion whose evidence design was removed, see below), `covered_paths` (space-separated repository-relative pathspecs whose change expires the
evidence, or `-`) and `check` (a script in `standard/checks/`, or `-`).

**Per criterion.** The newest record by date gives the recorded score. The current score is 0 when any of these holds,
otherwise it equals the recorded score:

| state | cause |
|---|---|
| expired | today is after the record date plus 90 days, or after the explicit date on the `Expires` line |
| expired | the record's commit is not in the repository |
| expired | `git diff --quiet <commit> HEAD -- <covered_paths>` reports a change |
| contradicted | the criterion's check script exits non-zero |
| none | the criterion has no record (current score 0, nothing to ratchet against) |

**Checks.** A script prints lines of the form `CHECK <id> <requirement> PASS|FAIL|INFO <detail>` and exits 1 when a
property that any positive score depends on is broken, 0 otherwise. An exit code other than 0 or 1 counts as broken.
A check that fails for a criterion with no record changes no score. Scripts print counts, or `file:line` plus the
matched token, never whole lines.

**Retired evidence.** A row with `measured_by` `retired` shows state `retired evidence (ADR 0020)`, current score 0 and
no ratchet check, whatever records exist. It claims nothing; the criterion text stays until the owner rewrites or drops
it. Row 1.5 is the only one today: its domain-fed egress allowlist was removed with the previous host's firewall role.

**Published evidence.** The summary ends its table with one line counting the phases and files under
`docs/evidence/`. It is a pointer count, not a score input (section 8).

**Ratchet.** If the current score is below the newest recorded score and there is no
`standard/evidence/<id>/<date>-ack.md` dated on or after that record, the run exits 1. This is by design on
2027-01-04: every record seeded on 2026-10-06 expires that day, and the scorecard turns red until each criterion is
measured again or acknowledged.

**Composite.** 2 x the sum of current scores. While `standard/blocking.md` has any row whose status is `open`, the
composite is capped at 49. Bands: 0-49 REJECTED, 50-79 APPROVED WITH CONDITIONS, 80-100 APPROVED. The output also
lists the open blocking conditions and, per failing check, its first failing lines.

**Exit code.** 1 only on a ratchet violation or an unreadable record. `SCORECARD_TODAY=YYYY-MM-DD` overrides today's
date, for tests. The scorer is standard-library Python 3; its tests are `python3 standard/tests/test_scorecard.py`.

---

## 8. Published phase evidence (`docs/evidence/`)

The platform repository holds sanitized runs of the real host under `docs/evidence/phase<N>/`, each phase with an
`INDEX.md` that names the claim every file backs (ADR 0052, release requirement R20). They are the raw material for
records: a record under `standard/evidence/<criterion>/` cites them and states which requirement each file shows.
**A pointer below is not a record and scores nothing.** A criterion stays at 0 until a dated record exists.

| criterion | current published evidence | what it does not show |
|---|---|---|
| 1.1 | none yet; `scripts/proxmox/ephemeral/` is code only, no runner is registered | every part |
| 1.2 | [golden-template build run](../docs/evidence/phase3/build-weekly-3.txt), [clone of the Docker template](../docs/evidence/phase3/evidence-vm-clone.txt) | a fresh instance per job, injected credentials, the canary pair |
| 1.3 | [R15 red first](../docs/evidence/phase2/r15-red-first-lxc.txt), [R15 baseline](../docs/evidence/phase2/r15-baseline-lxc.txt), [R15 after a host reboot](../docs/evidence/phase2/r15-after-pve-reboot-lxc.txt), [R15 from the cache container](../docs/evidence/phase4/r15-after-pve-reboot-cache.txt), [port ACL acceptance](../docs/evidence/phase1/acl-probe-20261006-152843.log) | the mapping of each requirement to a file, which a record must make |
| 1.4 | [provisioner token boundary](../docs/evidence/phase3/evidence-token-more.txt), [rollback and token proof](../docs/evidence/phase3/proof-rollback-token.txt) | the job user's root access, the writer environment branch policy |
| 1.5 | retired evidence (ADR 0020); ADR 0027 describes the current public-IPv4-only guest egress, a different requirement | all of the criterion as written |
| 2.1, 2.3 | [second probe apply without drift](../docs/evidence/phase2/probe-tofu-apply2.txt), [host stack plan without changes](../docs/evidence/phase4/tofu-proxmox-host-final-plan.txt) | a scheduled drift job, two consecutive playbook runs recorded by CI |
| 3.2 | [guest firewall guard journal](../docs/evidence/phase4/guard-after-ct-2.txt), [cache counters after the loop](../docs/evidence/phase4/metrics-after-loop.txt) | alerts and measured time to detect |
| 5.2 | [twenty-iteration cache loop](../docs/evidence/phase4/cache-loop20-results.txt), hosted full-suite run 37355482969 (requirements row 15, hosted baseline) | a scheduled job that exercises each path |

Rows not listed have no published evidence.
