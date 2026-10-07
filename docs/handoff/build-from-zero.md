# Build from zero

The order below is the order in which the reference implementation was built, with the check that proves each step. It is the outline for the Phase 8 timed rebuild, which has not been run: the first rebuild by the receiving team should be timed and every deviation recorded (R2, R18). Commands are not copied here; each step points to the [runbook](../../RUNBOOK.md) section (number and title; the runbook's section 2, "Build from zero", follows the same order) and, where it adds detail, to the component guide in the repository.

Runbook section numbers cited below are those of the rewritten runbook (2.1 to 2.9 build, 3.x day 2, 4.x verification); if the runbook is renumbered, keep the titles.

## Prerequisites

| Need | Reference setup | Evidence |
|---|---|---|
| A workstation that can run Hyper-V with nested virtualization | Windows 11 Pro, 8-core AMD CPU, 43.8 GiB RAM; nested KVM works with Memory Integrity on | rows 2, 3, 36 |
| Budget for the PVE VM | 12 vCPU, 20 GiB static RAM, 128 GiB dynamic VHDX; C: keeps at least 20 GiB free | D19, rows 28, 29 |
| An operator shell with a Linux toolchain | WSL Debian | ADR 0010 |
| A repository the team administers, with `gh` authenticated for it | A fork of this one | R16, R18 |
| New credentials for everything | Generated locally, never reused from this repository's history | R13 |

The SOPS files in `iac/secrets/` are encrypted to the reference operator's key and cannot be read by anyone else. Create an age identity first, put its public recipient into `.sops.yaml`, then generate every value again (root password, API token, state passphrase, cache writer password). Keep an off-machine copy of the identity before the PVE install, because a lost identity makes every secret unrecoverable (D29; [secrets README](../../iac/secrets/README.md)).

## Order, roles and proofs

| # | Step | Role | Guide | Proof that the step is done | Evidence |
|---|---|---|---|---|---|
| 1 | Install the operator toolchain with pinned, hash-verified binaries; create the age identity | operator | Runbook 2.1 "Workstation prerequisites"; [`scripts/bootstrap/operator-toolchain.sh`](../../scripts/bootstrap/operator-toolchain.sh), [secrets README](../../iac/secrets/README.md) | The script exits 0; `sops -d` of a test file works; a secret scan of the working tree finds 0 | ADR 0009, 0010; R13 |
| 2 | Enable Hyper-V, prepare the unattended install ISO, create the VM and install PVE 9.1 | host administrator (elevation, reboot), operator | Runbook 2.2 "Prepared install ISO" and 2.3 "The PVE VM (Hyper-V)"; [`scripts/hyperv/README.md`](../../scripts/hyperv/README.md) | `pveversion` prints `pve-manager/9.`; `/dev/kvm` exists and `kvm_amd nested` is 1; 18 port ACLs read back before the adapter connects; checkpoint `post-install` exists; WSL and Docker Desktop still work (the regression gate) | rows 35, 36, 40; [phase 1 index](../evidence/phase1/INDEX.md); ADR 0004, 0007, 0014 |
| 3 | Render the SSH config with the pinned host key, bootstrap the automation user, converge the host | operator | Runbook 2.4 "Host converge"; [Ansible README](../../iac/ansible/README.md), `scripts/iac/ansible.sh` | A second `site.yml` run ends `changed=0`; password login and the control key as root are refused; `hv_sock` is not loaded; the guard timer is active | rows 43, 46, 47; ADR 0022, 0023, 0028 |
| 4 | Confirm the API identity and the firewall (both are roles of the same converge) | operator | Runbook 2.4 "Host converge" and 2.6 "Guard and firewall checks"; roles `pve_api_identity`, `pve_firewall` | The provisioner token answers `/version` with 200 and refuses to create a user (403); effective privileges are only the scoped paths; the firewall is enabled and the dead-man did not fire | rows 46, 48; ADR 0026, 0027 |
| 5 | Apply the host OpenTofu stack: guest vnet, subnet, SNAT, and later the cache vnet | operator | Runbook 2.5 "OpenTofu host stack (guest network)"; [OpenTofu README](../../iac/tofu/README.md), [host stack README](../../iac/tofu/stacks/proxmox-host/README.md), `scripts/iac/tofu.sh` | `plan -detailed-exitcode` exits 0 after apply; the state file is mode 600 and holds `encrypted_data` only; a concurrent plan is refused by the lock; a wrong passphrase fails | rows 49, 50; [tofu-reds.txt](../evidence/phase2/tofu-reds.txt); ADR 0013, 0030 |
| 6 | Converge the template role, build both classes, check status and rollback | operator, root on pve01 | Runbook 2.7 "Golden templates"; day 2 in 3.3 "Golden templates" (includes consuming and pinning a template) | `homelab-template status` exits 0 with one `current` per class; after a second build each class holds two versions; rollback moves `current` back and forward again; each manifest hashes to the value in its template description; the provisioner token gets 403 on delete and retag, 200 on clone | rows 55-57; [phase 3 index](../evidence/phase3/INDEX.md); ADR 0038-0044 |
| 7 | Prove isolation (R15): red first, paired controls, after a container restart, a PVE reboot and a host reboot | operator | Runbook 2.8 "R15 verification (probe stack and `r15-verify.yml`)"; [isolation tests README](../../tests/isolation/README.md) | With the PVE firewall stopped the gateway and management rows are open (the proof can fail); with it on every negative is blocked and the egress positive is 200, in every phase; the counts at the reference end state are in [results.md](results.md) | rows 51, 52, 59, 66; ADR 0031, 0032, 0044 |
| 8 | Add the cache network and service: converge, apply the host stack for the cache vnet, create the container stopped, start it through the firewall read-back gate, set the writer credential | operator; repository administrator sets the environment branch policy | Runbook 2.9 "Cache service (`cache01`, VMID 9050, vnet `cache`)" and 2.6 "Guard and firewall checks" | The host plan shows only the cache vnet and subnet added; from a runner clone anonymous read 404 then 200, anonymous write 401, wrong password 401, writer write 200, a digest mismatch rejected with nothing stored; R15 re-run includes the cache rows | rows 61, 62, 66; [cache-api.txt](../evidence/phase4/cache-api.txt); ADR 0045, 0046, 0048, 0050 |
| 9 | Wire the client into the workflows and measure the hit ratio | operator | Runbook 3.4 "Cache: health, purge, rotation" (client wiring) and 4.2 "Host proofs (real host)" | The hosted fallback runs green with the cache disabled; on a runner-template clone an unchanged lockfile hits every restore after the first run; the stale-binary test is red on the stale variant and green on the new design | rows 63, 64, 68; ADR 0049, 0053 |
| 10 | Publish the evidence and knowledge pages | operator | Runbook 4.3 "Publishing evidence"; [knowledge README](../knowledge/README.md) | The evidence checker exits 0; each index row carries a raw and a published hash | row 69; ADR 0052 |

Re-run the R15 probe after every step that changes a firewall, a vnet, a template or the guard (ADR 0031).

## Owner-only steps in this order

| When | Step | Source |
|---|---|---|
| Step 2 | Accept the elevation prompt; reboot after enabling Hyper-V; sign in again so Hyper-V Administrators membership applies | R1, D26, D36 |
| Before step 2 | Keep the age identity and the root password off the machine | D29 |
| Step 8 | Environment `cache-writer`: Deployment branches and tags set to the default branch only, then rotate the writer password | ADR 0050; [security-model.md](security-model.md) |
| Before any runner (Phase 5) | Set fork pull-request approval to all external contributors | row 27; [next-phases.md](next-phases.md) |

## What a rebuild is not yet proven to do

- Phase 8's clause "a reader who was not part of the work rebuilds from the runbook alone" has not been tested (R18).
- Steps 6, 7, 8 and 9 were built on one host in one session each; the weekly timer has fired once (row 56), not over weeks.
- Nothing here creates a runner; that starts in [next-phases.md](next-phases.md).
