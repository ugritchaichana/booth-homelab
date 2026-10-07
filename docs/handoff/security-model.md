# Security model

The central risk is R15: code from a public repository runs in runner guests on a host that routes private prefixes, a mesh VPN and a home LAN. A runner must reach none of them, nor the hypervisor host, nor the PVE management interface (R15, row 22, D17). Everything below serves that rule, then the integrity of what runners produce (templates, cache).

## R15 layers

| Layer | Where | What it blocks | Added by |
|---|---|---|---|
| Switch port ACLs | Hyper-V, on the VM's adapter, outside the VM | RFC 1918, CGNAT, link-local, every prefix the host routes through a non-default interface (read at each VM start), IPv6; replies to host-opened sessions allowed | D37, ADR 0007 |
| Windows firewall rule | Windows host, on the internal vEthernet | Inbound from the VM subnet | D37 |
| PVE firewall | pve01, classic firewall, cluster plus host plus per-guest | Management reachable only from the management address; guests get `policy_out DROP`, ipfilter, macfilter and the group `guest-egress` | D53, ADR 0027 |
| Port isolation | SDN vnet `guests` | Guest to guest, even with the firewall stopped | D54, row 51 |
| Guard | pve01, per-vnet policy | A guest that lacks any of the above is stopped | D65, D75 |
| Transport removals | pve01 | `hv_sock` blocked; IPv6 forwarding, accept_ra and autoconf off | D62, rows 47, 50 |

Layers 1 and 2 are the host layer and exist only on the reference setup; on bare metal the PVE firewall, port isolation and guard remain ([porting.md](porting.md)).

## How R15 is proven

- Red first. Every run starts with the PVE firewall stopped: the gateway and management rows must be open, so the proof can fail. Phase 2 measured gateway and management SSH and web console open while every external row stayed dropped by the Windows layer (row 51). The phase 4 red-first runs repeat this per class: [lxc](../evidence/phase4/r15-red-first-lxc.txt), [vm](../evidence/phase4/r15-red-first-vm.txt), [cache](../evidence/phase4/r15-red-first-cache.txt) (row 66).
- Paired controls. Every negative is paired with a positive control (for example the same target reached from the host), so a block cannot be confused with an absent service; one egress positive runs every time (D55, ADR 0031).
- One run per restart phase: baseline, container restart, PVE reboot, laptop reboot. At the reference end state runners show `negatives_blocked=19/19 positives_ok=2/2` and the cache container `12/12 1/1`, again after a pve01 reboot ([baseline](../evidence/phase4/r15-baseline-lxc.txt), [after reboot](../evidence/phase4/r15-after-pve-reboot-lxc.txt); row 66). The switch layer alone, with the Windows rule disabled for 10.6 s, still blocked guest to host tcp 445 (row 42).
- Drift check: per-guest options are compared with the runner-class policy on every run (D55).
- Probes run in guests cloned from the real templates, not hand-built ones (ADR 0044, D80). They are not real JIT runners: the proof from a real runner is a Phase 5 entry gate.

Not measured, in every phase: a peer's web service over the VPN and a host inside the harvested prefixes. No Windows-side positive exists for them, so a block cannot be told from an absent service (rows 38, 42, 52). Re-measure on the target network before trusting them ([porting.md](porting.md)). ICMP to the internet fails by design (stateful TCP and UDP only, row 38).

## Tokens and boundaries

| Token or identity | Boundary | Proof |
|---|---|---|
| Provisioner API token (`tofu@pve!provisioner`) | Privilege-separated; pool `homelab` guest lifecycle, SDN use on the two vnets, `VM.Clone` on pool `templates`; no create-user, no volume delete, no storage config | Create user 403; effective privileges listed in row 48 |
| Template clone | A role holding only `VM.Clone` and `VM.Audit` on pool `templates`, assigned nowhere else, asserted by the role and a CI test | Token 403 deleting and retagging a template, 200 cloning it (row 57; [proof-rollback-token.txt](../evidence/phase3/proof-rollback-token.txt)); ADR 0036 |
| Root orchestrator | Root builds, promotes and rolls back; the guest-facing step is non-root and sandboxed; the host chooses every argument and never parses guest output | `tests/isolation/test-template-guest-step.sh`; ADR 0038 |
| Controller (Phase 5) | Must hold no privilege on the cache container's pool or the cache vnet | Gate, see [next-phases.md](next-phases.md) |

Two limits of the provisioner token that the receiving team will meet: it cannot set tags at create (the permission is checked without the pool), and the cache container currently sits in pool `homelab`, where the token can stop or re-address it (row 48; Phase 4 security review, summarized in [next-phases.md](next-phases.md)).

## Cache write boundary and its owner step

- Reads are anonymous: a pull-request job holds nothing to leak. Writes need one credential (`ci-writer`), held only as the secret `CACHE_WRITER_PASSWORD` of environment `cache-writer` (ADR 0050).
- The credential sits only in the environment of the save steps. Those steps run the cache client over artifacts uploaded by the same run's build and test jobs, so no install script or build runs beside it. A workflow test rejects any use of the secret outside the save steps (row 70, cache CI run 37602586953).
- The server verifies the sha256 of every blob on upload (500 on mismatch, nothing stored); the client verifies digests on restore, extracts only the planned paths, caps size and members, and refuses an interpreter older than the tarfile fixes (rows 62, 65, 70).
- Owner step, not done: environment `cache-writer` has no deployment branch policy (`deployment_branch_policy: null`, read 2026-10-07). Until the repository administrator restricts it to the default branch, a workflow from any branch of the same repository can name the environment and receive the credential; forks never receive it (ADR 0050; Phase 4 security review). After setting the policy, rotate the password so a value readable earlier is replaced ([operations.md](operations.md)).
- Traffic is plain HTTP on a private vnet; Basic credentials are visible to anything that can sniff that segment (ADR 0050). Revisit before the cache leaves the host.

## Secrets handling

- SOPS plus age, one file per consumer and host, one writer each; values reach `sops` on stdin, never on a command line; tasks that touch them run under `no_log` (D52, ADR 0033).
- Listings show names only (R13); a secret scan (gitleaks) runs in CI; the root-password hash exists in the install ISO and answer file only until the install, then is deleted (D38).
- Published evidence is sanitized by exact value from an operator-local map, a checker flags and never rewrites, and the deny list stays outside the repository (D81, ADR 0052). Hash-anchored files are published unchanged or withheld.
- Single age recipient: a lost identity loses everything, a leaked one means changing every value ([secrets README](../../iac/secrets/README.md)).

## Known gaps (details and closure in [limits-and-gaps.md](limits-and-gaps.md))

| Gap | One line |
|---|---|
| Cache-writer branch policy unset | Owner setting; any branch workflow of the repository can receive the credential until set |
| Fork pull-request approval unset | The routing expression still selects self-hosted for fork pull requests (row 27); a Phase 5 entry gate |
| Writer jobs never executed | No self-hosted runner exists, so the save jobs have never run in environment `cache-writer` on the new platform (row 68) |
| Cache egress | `cache01` keeps public egress through `guest-egress`; a compromised cache could call out (Phase 4 security review) |
| Guard alerting | An unreadable policy exits 4 without a marker or alert; the ipset contents are not checked (Phase 4 security review) |
| bazel-remote crash finding | 2.6.2 serves a partially written blob after `kill -9`; mitigated by a start-time sweep, not fixed upstream here (row 65) |
| Sudo on VM clones | cloud-init restores the default user's passwordless sudo at a clone's first boot; no fix yet (row 59) |
| Provisioner token reaches the cache container | Same pool as guests (Phase 4 security review) |
