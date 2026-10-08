# Limits and gaps

Every named gap, who owns it, and the evidence that closes it. "Owner" means the repository administrator. Phase numbers refer to [next-phases.md](next-phases.md). A gap is closed only by the evidence in the last column, not by a statement.

## Security gaps

| Gap | Owner step | What closes it | Source |
|---|---|---|---|
| Fork pull-request approval: set to "all external contributors" on 2026-10-08 ([read-back](../evidence/closeout/owner-gaps-readback.txt)), not yet shown on a real fork pull request | Repository administrator with a second account, or Phase 6 | A fork pull-request run shown not to start without approval | row 27 (routing), owner actions in requirements.md |
| The routing expression sends fork pull requests to self-hosted runners | Phase 5 gate, then the Phase 6 router | Fork events routed to hosted in the workflows; a fork run on hosted shown by a run id | row 27 (routing); D17 (public-repo CI on a host with private networks) |
| Save jobs have never run in environment `cache-writer` on the new platform; the self-hosted path has never run, and hosted CI does not use the cache ([ADR 0054](../adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md)) | Phase 5 first runners; Phase 6 | A default-branch push runs the save jobs on a JIT runner, a later run hits, and a canary proves the writer credential is absent from every step that runs third-party code | row 68 (hosted run); ADR 0053 |
| Cache egress: the cache container keeps public IPv4 egress through `guest-egress`, so a compromised cache service could call out | Phase 7 | An egress group without `public-v4` for the cache, opened only during converge; R15 cache rows show the outbound negative | Phase 4 security review |
| Guard alerting: an unreadable policy makes the guard exit 4 with no marker and no alert; the contents of the ipfilter ipset are not checked | Phase 7 | A marker and an `OnFailure` alert on that exit, an ipset content check, and tests that fail without them | Phase 4 security review; ADR 0047 |
| bazel-remote 2.6.2 serves a partially written file after `kill -9` | Operator, on each version bump | Keep the start-time sweep (`tests/isolation/test-cache-verify-cas.sh`); repeat the `kill -9` check against every new bazel-remote version | row 65 (cache edge cases); [cache-kill9-check.txt](../evidence/phase4/cache-kill9-check.txt) |
| cloud-init restores the default user's passwordless sudo at a VM clone's first boot, although the template seal removed it | Phase 5 gate | A fix plus an R15 row that fails if a runner clone can use sudo | row 59 (clone isolation); [evidence-vm-clone.txt](../evidence/phase3/evidence-vm-clone.txt) |
| The provisioner token holds privileges on the pool that contains the cache container, and `SDN.Use` on the cache vnet | Phase 5 gate (the controller must not hold it) | A separate pool without a provisioner ACL and an operator-scoped token for the cache stack; `pvesh set` on the cache container returns 403 with the controller token | Phase 4 security review |
| Plain HTTP with Basic credentials between runners and cache | Before the cache leaves one host | A decision (TLS or an isolated segment) recorded in an ADR | ADR 0050 |
| No TOTP on `root@pam`; notification target absent | Owner (enrolment) and Phase 7 | Enrolment done; a notification target tested | D60 (TOTP and notifications) |
| Host-layer trust: any process running as the owner can change the VM's port ACLs; the claim that this reaches host-administrator rights is a HYPOTHESIS, untested | Host layer only; drops on bare metal | Not applicable on bare metal | D43 (Hyper-V Administrators re-confirmed) |

## Entry gates for the controller phase (Phase 5)

All gates must be shown, not asserted, before the first runner registers. The full list is in [next-phases.md](next-phases.md).

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
| Suite time, queue-to-start and scale-from-zero targets unmeasured | Phase 5 load test and Phase 6 five consecutive runs with a baseline-versus-after table | requirements.md section 8 |
| R15 rows never measured: a VPN peer's web service, a host inside the harvested prefixes | A Windows-side positive control, or a re-measurement on the target network | row 38 (host-side layer), row 42 (after reboot), row 52 (per-guest runs) |
| Thresholds for the build space guard (data 70%, metadata 70%, 8 GiB free) are placeholders | A measurement under realistic load | role defaults of `pve_templates` |
| The weekly timer fired once; never observed over weeks | A month of timer runs with an alert | row 56 (retention and rollback) |
| Secret rotations ([runbook 3.5](../../RUNBOOK.md)) are implemented but no host run is recorded | Drills in Phase 7 | [operations.md](operations.md) |
| The dependency cache is not faster than a network install at the sample app's size; one cold run only | More cold runs, and a larger app | [results.md](results.md) |

## Process and tooling gaps

| Gap | What closes it | Source |
|---|---|---|
| Backups to another device, general object storage and a timed restore do not exist | Phase 7 | [next-phases.md](next-phases.md) |
| OpenTofu state is local to one operator workstation | A shared, locked, encrypted backend chosen by the receiving team (not the cache) | ADR 0013, 0051 |
| A second real host was planned, never applied | Adding a host by [operations.md](operations.md) | R5 (baseline capabilities) |
| Rebuild from zero by someone who was not there; run on a non-Proxmox host | Phase 8 | R2 (runbook), R10 (portability), R18 (handoff-ready) |
| The probe's link-local target is a stale hand-edited value after an SDN re-apply | The probe derives the address at run time | [real-host-defects.md](../knowledge/real-host-defects.md), open findings |
| Provisioner cannot set tags at create; deleting a downloaded volume needs one operator `pvesm free` | Accepted limitation; do not widen the token | row 48 (token boundary) |
| Janitor for runs stuck on offline self-hosted runners | Phase 6 backlog, see [next-phases.md](next-phases.md) | closed pull request [#49](https://github.com/ugritchaichana/booth-homelab/pull/49), "feat: actions janitor cancels runs stuck on offline self-hosted runners and raises an alert issue" |
| Old copies of three renamed wiki pages stay on the GitHub wiki | Owner deletes them in the wiki's page settings; the repository cannot | [previous-agent-debt.md](../knowledge/previous-agent-debt.md) |
| No `global.json` pins the .NET SDK | Add one only if a template build ever picks the wrong SDK | ADR 0049 |

## Code-structure gaps (named in the close-out review, not fixed)

Each needs a host converge proof or is Phase 5 work.

- The dead-man logic in the `base` and `pve_firewall` roles is not extracted into one role.
- `iac/ansible/playbooks/site.yml` has two near-identical `pre_tasks` blocks.
- `iac/ansible/playbooks/r15-verify.yml` loads `iac/tofu/stacks/r15-probe/probe.yml`, the data file of the OpenTofu probe stack, so the Ansible play depends on that stack's layout.
- No stub test covers `scripts/iac/tofu.sh`, `scripts/hyperv/New-PveHost.ps1`, `scripts/proxmox/build-auto-install-iso.sh` or `scripts/bootstrap/operator-toolchain.sh`; `render-ssh-config.sh` and `Invoke-PveVm.ps1` have tests now.
- `scripts/proxmox/ephemeral/` sits beside the install scripts but belongs to the Phase 5 runner design; decide its home there ([next-phases.md](next-phases.md), Phase 5 starting points).
- `.github/workflows/sdet-ci.yml` passes `secrets: inherit` to the reusable pipeline instead of naming the secrets it needs.
- `scripts/iac/cache-writer-secret.sh`, `new-guest.sh`, `render-ssh-config.sh` and `tofu.sh` each define their own helper functions such as `die`; there is no shared `scripts/iac/lib.sh`.

## Closed gaps

| Gap | Closed | Evidence |
|---|---|---|
| Cache-writer branch policy: a workflow from any branch could name environment `cache-writer` and receive the writer credential | 2026-10-08: selected branches, `master` only; the writer password rotated afterwards and converged on the cache host | [owner-gaps-readback.txt](../evidence/closeout/owner-gaps-readback.txt), [rotate-converge-2.txt](../evidence/closeout/rotate-converge-2.txt) |
| The two old runners of the retired host were still registered | 2026-10-08: deregistered; the runners API lists 0 runners | [owner-gaps-readback.txt](../evidence/closeout/owner-gaps-readback.txt) |

## Reference-machine limits (do not inherit)

A laptop that enters Modern Standby suspends the VM and invalidates long runs (row 43, converge run); static RAM leaves little for daily work (row 28, RAM headroom); the control path through the Windows host and WSL has no bare-metal equivalent (ADR 0011). See [porting.md](porting.md).
