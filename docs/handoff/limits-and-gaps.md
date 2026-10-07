# Limits and gaps

Every named gap, the role or phase that owns it, and what evidence closes it. "Owner" means the repository administrator in the source documents; Phase numbers refer to [next-phases.md](next-phases.md). A gap is closed only by the evidence in the last column, not by a statement.

## Security gaps

| Gap | Owner step | What closes it | Source |
|---|---|---|---|
| Environment `cache-writer` has no deployment branch policy: a workflow from any branch of the repository can name it and receive the writer credential | Repository administrator, before the first runner (Phase 5 gate) | Setting "selected branches" to the default branch only; then rotate the writer password; read back `deployment_branch_policy` non-null | ADR 0050; rows 62, 70 |
| Fork pull-request approval is not set to "all external contributors" | Repository administrator, now | The setting changed, and a fork pull-request run shown not to start without approval | row 27, owner actions in requirements.md |
| The routing expression sends fork pull requests to self-hosted runners | Phase 5 gate, then Phase 6 router | Fork events routed to hosted in the workflows; a fork run on hosted shown by a run id | rows 27, D17 |
| Writer (save) jobs have never executed in environment `cache-writer` on the new platform; the self-hosted path has never run | Phase 5 first runners; Phase 6 | A default-branch push runs the save jobs on a JIT runner, a later run hits, and a canary proves the writer credential is absent from every step that runs third-party code | rows 63, 68; ADR 0053 |
| Cache egress: `cache01` keeps public IPv4 egress through `guest-egress`, so a compromised cache service could call out | Phase 7 | An egress group without `public-v4` for the cache, opened only during converge; R15 cache rows show the outbound negative | Phase 4 security review |
| Guard alerting: an unreadable policy makes the guard exit 4 with no marker and no alert; the contents of the ipfilter ipset are not checked | Phase 7 | A marker and an `OnFailure` alert on that exit, an ipset content check, and tests that fail without them | Phase 4 security review; ADR 0047 |
| bazel-remote 2.6.2 serves a partially written file after `kill -9` | Operator, on each version bump | Keep the start-time sweep (`tests/isolation/test-cache-verify-cas.sh`); repeat the `kill -9` check against every new bazel-remote version; an alert when the quarantine directory is not empty is a proposal, not built | row 65; [cache-kill9-check.txt](../evidence/phase4/cache-kill9-check.txt) |
| cloud-init restores the default user's passwordless sudo at a VM clone's first boot, although the template seal removed it | Phase 5 gate | A fix plus an R15 row that fails if a runner clone can use sudo | row 59; [evidence-vm-clone.txt](../evidence/phase3/evidence-vm-clone.txt) |
| The provisioner token holds privileges on the pool that contains the cache container, and `SDN.Use` on the cache vnet | Phase 5 gate (the controller must not hold it) | A separate pool without a provisioner ACL and an operator-scoped token for the cache stack; `pvesh set` on the cache container returns 403 with the controller token | Phase 4 security review |
| Plain HTTP with Basic credentials between runners and cache | Before the cache leaves one host | A decision (TLS or an isolated segment) recorded in an ADR | ADR 0050 |
| No TOTP on `root@pam`; notification target absent | Owner (enrolment) and Phase 7 | Enrolment done; a notification target tested | D60 |
| Host-layer trust: any process running as the owner can change the VM's port ACLs; the claim that this reaches host-administrator rights is a HYPOTHESIS, untested | Host layer only; drops on bare metal | Not applicable on bare metal | D43 |

## Entry gates for the controller phase (Phase 5)

All gates below must be shown, not asserted, before the first runner registers. The full list with the research it depends on is in [next-phases.md](next-phases.md).

| Gate | What closes it |
|---|---|
| Runner clones do not keep sudo | R15 row plus the fix above |
| Root acts on probe guests only after checking tag and pool; runner VMIDs stay outside the template blocks | Test of the check; VMID allocation rule in the controller |
| Per-runner firewall read-back (clones inherit the template firewall) | Read-back before first start, a failing test when a setting differs |
| Alert on stale templates or failed builds, and a path to bump the runner pin | An alert firing in a drill; the runbook 3.3 bump procedures exercised |
| Alarm on cache writes outside writer-job windows | Access-log alarm tested with a synthetic write |
| Thin-pool headroom guard for runner disks and the cache volume | Guard refuses a clone above a measured threshold (the build thresholds today are unmeasured placeholders) |
| A host converge that would reboot drains the pool first | Converge play that waits for a drained pool |
| R15 re-run from a real JIT runner, including the cache-vnet negatives | Run outputs stored like the phase 4 files |
| Runners are JIT and ephemeral before any pull-request job | `gh api .../actions/runners` lists `ephemeral: true` for every runner |

## Measurement gaps

| Gap | What closes it | Source |
|---|---|---|
| Suite time, queue-to-start and scale-from-zero targets unmeasured | Phase 5 load test and Phase 6 five consecutive runs with a baseline-versus-after table | Q7; requirements.md section 8 |
| R15 rows never measured: a VPN peer's web service, a host inside the harvested prefixes | A Windows-side positive control, or a re-measurement on the target network | rows 38, 42, 52 |
| Thresholds for the build space guard (data 70%, metadata 70%, 8 GiB free) are placeholders | A measurement under realistic load | role defaults of `pve_templates` |
| The weekly timer fired once; never observed over weeks | A month of timer runs with the alert from above | row 56 |
| Secret rotations (runbook 3.5) are implemented but no host run is recorded | Drills in Phase 7 | [operations.md](operations.md) |

## Process and tooling gaps

| Gap | What closes it | Source |
|---|---|---|
| Backups to another device and a timed restore do not exist | Phase 7 | requirements.md section 5, Phase 7 |
| OpenTofu state is local to one operator workstation | A shared, locked, encrypted backend chosen by the receiving team (not the cache) | ADR 0013, 0051 |
| A second real host was planned, never applied | Adding a host by [operations.md](operations.md) | R5 |
| Rebuild from zero by someone who was not there; run on a non-Proxmox host | Phase 8 | R2, R10, R18 |
| Old runners of the retired host are still registered | Repository administrator deregisters them on an explicit go (Phase 6) | row 27; section 2.1 row 11 |
| The probe's link-local target is a stale hand-edited value after an SDN re-apply | The probe derives the address at run time | [real-host-defects.md](../knowledge/real-host-defects.md), open item |
| Provisioner cannot set tags at create; deleting a downloaded volume needs one operator `pvesm free` | Accepted limitation; do not widen the token | row 48 |

## Reference-machine limits (do not inherit)

A laptop that enters Modern Standby suspends the VM and invalidates long runs (row 43); static RAM leaves little for daily work (rows 28, 40); the control path through the Windows host and WSL has no bare-metal equivalent (ADR 0011). See [porting.md](porting.md).
