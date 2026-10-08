# Security model

The central risk is R15 (runners cannot reach any private network the host is attached to): code from a public repository runs in runner guests on a host that routes private prefixes, a mesh VPN and a home LAN. A runner must reach none of them, nor the hypervisor host, nor the PVE management interface (row 22, host VPN routes; D17, public-repo CI on a host with private networks). Everything below serves that rule, then the integrity of what runners produce (templates, cache).

## R15 layers

| Layer | Where | What it blocks | Added by |
|---|---|---|---|
| Switch port ACLs | Hyper-V, on the VM's adapter, outside the VM | RFC 1918, CGNAT, link-local, every prefix the host routes through a non-default interface (read at each VM start), IPv6; replies to host-opened sessions allowed | ADR 0007 |
| Windows firewall rule | Windows host, on the internal vEthernet | Inbound from the VM subnet | ADR 0007 |
| PVE firewall | pve01, classic firewall, cluster plus host plus per-guest | Management reachable only from the management address; guests get `policy_out DROP`, ipfilter, macfilter and the group `guest-egress` | ADR 0027 |
| Port isolation | SDN vnet `guests` | Guest to guest, even with the firewall stopped | ADR 0030; row 51 (red-first isolation) |
| Guard | pve01, per-vnet policy | A guest that lacks any of the above is stopped | ADR 0037, 0047 |
| Transport removals | pve01 | `hv_sock` blocked; IPv6 forwarding, accept_ra and autoconf off | ADR 0028; row 50 (guest network) |

Layers 1 and 2 are the host layer and exist only on the reference setup; on bare metal the PVE firewall, port isolation and guard remain ([porting.md](porting.md)).

## How R15 is proven

- Red first. Every run starts with the PVE firewall stopped: the gateway and management rows must be open, so the proof can fail. Phase 2 measured gateway and management SSH and web console open while every external row stayed dropped by the Windows layer (row 51, red-first isolation). The phase 4 red-first runs repeat this per class: [lxc](../evidence/phase4/r15-red-first-lxc.txt), [vm](../evidence/phase4/r15-red-first-vm.txt), [cache](../evidence/phase4/r15-red-first-cache.txt) (row 66, R15 with the cache path, R15 with the cache path).
- Paired controls. Every negative is paired with a positive control (for example the same target reached from the host), so a block cannot be confused with an absent service; one egress positive runs every time (ADR 0031).
- One run per restart phase: baseline, container restart, PVE reboot, laptop reboot. Counts at the reference end state: [results.md](results.md) ([baseline](../evidence/phase4/r15-baseline-lxc.txt), [after reboot](../evidence/phase4/r15-after-pve-reboot-lxc.txt)). The switch layer alone, with the Windows rule disabled, still blocked guest to host tcp 445 (row 42, ACLs after a reboot, ACLs after a reboot).
- Drift check: per-guest options are compared with the runner-class policy on every run.
- Probes run in guests cloned from the real templates, not hand-built ones (ADR 0044, ADR 0053). They are not real JIT runners: the proof from a real runner is a Phase 5 entry gate.

Not measured, in every phase: a peer's web service over the VPN and a host inside the harvested prefixes. No Windows-side positive exists for them, so a block cannot be told from an absent service (row 38, host-side layer; row 42, ACLs after a reboot, ACLs after a reboot; row 52, per-guest runs). Re-measure on the target network before trusting them ([porting.md](porting.md)). ICMP to the internet fails by design (stateful TCP and UDP only, row 38, host-side layer).

## Tokens and boundaries

| Token or identity | Boundary | Proof |
|---|---|---|
| Provisioner API token (`tofu@pve!provisioner`) | Privilege-separated; pool `homelab` guest lifecycle, SDN use on the two vnets, `VM.Clone` on pool `templates`; no create-user, no volume delete, no storage config | Create user 403; effective privileges listed in row 48 (token boundary) |
| Template clone | A role holding only `VM.Clone` and `VM.Audit` on pool `templates`, assigned nowhere else, asserted by the role and a CI test | Token 403 deleting and retagging a template, 200 cloning it (row 57, template protection; [proof-rollback-token.txt](../evidence/phase3/proof-rollback-token.txt)); ADR 0036 |
| Root orchestrator | Root builds, promotes and rolls back; the guest-facing step is non-root and sandboxed; the host chooses every argument and never parses guest output | `tests/isolation/test-template-guest-step.sh`; ADR 0038 |
| Controller (Phase 5) | Must hold no privilege on the cache container's pool or the cache vnet | Gate, see [next-phases.md](next-phases.md) |
| Runner status token (`RUNNER_STATUS_TOKEN`) | Fine-grained, this repository only, Administration read: it lists runners and cannot change code, secrets or settings. Only the route step of `Select Runner` reads it; forks never receive it. An expired or revoked token falls back to routing by `CI_RUNNER` | `tests/router/test_workflows.py` (one reader, with mutants); `HTTP 200` in the route reason; [ADR 0062](../adr/0062-route-ci-by-runner-health-and-retry-once-on-hosted-after-an-infra-failure.md) |
| Runner job-start hook (`scripts/ci/runner-guard.sh`, owned by root) | Fails a job before its first step unless the repository is this one and the event is a push, a dispatch, a schedule or a pull request from a branch of this repository; fork and `pull_request_target` jobs never run a step on the runner. The `runner` user has no sudo and cannot change the hook | `tests/isolation/test-runner-guard.sh`; the line `runner-guard: allowed` in every runner job log; [ADR 0060](../adr/0060-run-own-ci-on-one-persistent-runner-container-behind-a-job-start-guard.md) |

Two limits of the provisioner token that the receiving team will meet: it cannot set tags at create (the permission is checked without the pool), and the cache container currently sits in pool `homelab`, where the token can stop or re-address it (row 48, token boundary; Phase 4 security review, summarized in [next-phases.md](next-phases.md)).

## Cache write boundary and its owner step

- Reads are anonymous: a pull-request job holds nothing to leak. Writes need one credential (`ci-writer`), held only as the secret `CACHE_WRITER_PASSWORD` of environment `cache-writer` (ADR 0050).
- The credential sits only in the environment of the save steps. Those steps run the cache client over artifacts uploaded by the same run's .NET and Angular jobs, so no install script or build runs beside it. A workflow test rejects any use of the secret outside the save steps (row 70, security hardening; `tests/cache/test_workflow_secrets.py`).
- The server verifies the sha256 of every blob on upload (500 on mismatch, nothing stored); the client verifies digests on restore, extracts only the planned paths, caps size and members, and refuses an interpreter older than the tarfile fixes (row 62, cache API; row 65, cache edge cases; row 70, security hardening).
- Done 2026-10-08: environment `cache-writer` accepts only `master`, and the writer password was rotated after the policy was set ([limits-and-gaps.md](limits-and-gaps.md), closed gaps; ADR 0050).
- Traffic is plain HTTP on a private vnet; Basic credentials are visible to anything that can sniff that segment (ADR 0050). Revisit before the cache leaves the host.

## Secrets handling

- SOPS plus age, one file per consumer and host, one writer each; values reach `sops` on stdin, never on a command line; tasks that touch them run under `no_log` (ADR 0033).
- Listings show names only ; a secret scan (gitleaks) runs in CI; the root-password hash exists in the install ISO and answer file only until the install, then is deleted.
- Published evidence is sanitized by exact value from an operator-local map, a checker flags and never rewrites, and the deny list stays outside the repository (ADR 0052). Hash-anchored files are published unchanged or withheld.
- Single age recipient: a lost identity loses everything, a leaked one means changing every value ([secrets README](../../iac/secrets/README.md)).

## Flavor guests

A guest created by `scripts/iac/new-guest.sh` is a linked clone of a template, created stopped, with the NIC `firewall` flag, `ipfilter` for a VM and the `guests` bridge; it declares no firewall rules of its own and inherits the template's (ADR 0055). The guard stops one that lacks any of them. No new secret or role is involved: the stack uses the provisioner token.

## Lab defaults and what to turn on

This lab is a learning project and a base to adapt, so it leaves some controls off on purpose. Turn each on when its condition applies to your setup.

| Control | In this lab | Why | Turn it on when | How |
|---|---|---|---|---|
| TOTP on `root@pam` | Off | Every UI login would need a code; the UI is reachable only through the host relay, and `root@pam` is break-glass only | Someone other than the owner can reach the UI, a second administrator joins, the host carries real workloads, or the UI is exposed beyond the relay | [ADR 0058](../adr/0058-keep-proxmox-login-hardening-off-in-the-reference-lab.md) |
| Encrypted cache traffic | Plain HTTP with Basic credentials on a private vnet | One host, one isolated vnet | Before the cache leaves the host | [ADR 0050](../adr/0050-allow-anonymous-cache-reads-and-gate-writes-with-one-writer-credential.md) |
| A second age recipient | One recipient | One operator holds every secret | More than one person needs the secrets, or the identity must survive the loss of one copy | [secrets README](../../iac/secrets/README.md), recovery and rotation |
| Fork pull-request approval | Loosest GitHub allows: only accounts new to GitHub wait | Anyone can open a pull request and see CI run; merges still need the owner's review; fork jobs run on hosted runners and the runner's job-start hook refuses them | The job-start hook is removed, or a runner serves a repository without it | Settings, Actions, General; or `gh api -X PUT repos/OWNER/REPO/actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors` ([ADR 0059](../adr/0059-open-the-reference-lab-to-visitors.md)) |
| A different, strong root password on each machine | One shared root password on the host and every guest, plus a read-only visitor: `guest@pve` in the web UI (role `LabGuest`: `PVEAuditor` privileges plus `VM.Console`) and a local `guest` without administrative groups in each guest | Visitors log in and look around without setup; SSH on the host still refuses passwords | Before the host holds anything of value or anyone untrusted can reach the UI | Runbook 3.5, `iac/ansible/playbooks/lab-accounts.yml` ([ADR 0059](../adr/0059-open-the-reference-lab-to-visitors.md)) |
| Ephemeral (JIT) runners | One persistent container with three runner instances behind the job-start hook; state outside the checkout survives between jobs of one instance | Only the owner can start an event the hook allows: the owner is the only collaborator and Dependabot security updates are off | A second collaborator joins, an app or bot can push branches, or the runner serves another repository | Phase 5 pool ([next-phases.md](next-phases.md)); [ADR 0060](../adr/0060-run-own-ci-on-one-persistent-runner-container-behind-a-job-start-guard.md) |
| Status token out of reach of branch workflows | Any workflow on a branch of this repository can read `RUNNER_STATUS_TOKEN`; the route step is its only reader on `master` | The owner is the only collaborator, and the token is read-only: repository administration data such as runners and settings, no code, no secrets | A second collaborator joins, or an app or bot can push branches | Move the token to an environment that only `master` may use and give the route step that environment; pull-request runs then route by `CI_RUNNER` alone ([ADR 0062](../adr/0062-route-ci-by-runner-health-and-retry-once-on-hosted-after-an-infra-failure.md)) |
| A fresh VM checkpoint after each rotation | None after the 2026-10-08 writer rotation | A checkpoint needs the VM off, and the lab stays running (D86) | Every rotation that follows a checkpoint: an older checkpoint still holds the old secret | Runbook 3.1 |

## Known gaps

All open security gaps, with owner and closing evidence: [limits-and-gaps.md](limits-and-gaps.md).
