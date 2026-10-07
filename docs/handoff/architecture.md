# Architecture

Two layers, kept apart so an adopter can drop the first (R18, handoff-ready; R10, portable). The diagram is in the [README](../../README.md).

| Layer | Contents | Portable? |
|---|---|---|
| Windows host layer | Hyper-V VM, internal switch and NAT, switch port ACLs, Windows firewall rule, checkpoints, the PowerShell scripts under `scripts/hyperv/` | No. It exists only because the reference hypervisor is a nested guest on a workstation (ADR 0003) |
| Portable core | Proxmox roles (`iac/ansible/roles/`), OpenTofu stacks (`iac/tofu/stacks/`), inventory, golden templates, cache service and client, workflows, evidence tooling | Yes, to any Proxmox VE 9 host reachable over SSH; see [porting.md](porting.md) |

## Components

| Component | Where it lives | What it does | Decision |
|---|---|---|---|
| Inventory | `iac/inventory/hosts.yml` | The one host data file read by Ansible and OpenTofu; a host is an entry, not code | ADR 0018, 0021 |
| `base`, `hyperv_guest`, `pve_host` roles | `iac/ansible/roles/` | Key-only automation user, sshd hardening behind a dead-man, time sync; block `hv_sock`; repositories, upgrade, reboot on a new kernel | ADR 0005, 0023, 0028 |
| `pve_api_identity` role | same | Creates the OpenTofu user, roles, pools `homelab` and `templates`, ACLs and a privilege-separated token whose secret goes straight to SOPS | ADR 0026, 0036 |
| `pve_firewall` role | same | Renders `cluster.fw` and `host.fw`, runs the firewall dead-man, ships the guest firewall guard and its timer | ADR 0025, 0027, 0037, 0047 |
| `pve_templates` role | same | The root orchestrator `homelab-template`, the sandboxed guest-facing step, units, base images, snippets, the weekly rebuild timer | ADR 0038 to 0042 |
| `cache_service` role | same | bazel-remote pinned by sha256, writer credential as a bcrypt hash, hardened unit, start-time sweep | ADR 0048, 0050 |
| `proxmox-host` stack | `iac/tofu/stacks/proxmox-host/` | SDN zone `hlab`, vnets `guests` and `cache`, subnets, SNAT; selected by `var.host` | ADR 0030, 0045 |
| `cache-service` stack | `iac/tofu/stacks/cache-service/` | Container `build-cache-debian-13` on the cache vnet, created stopped | ADR 0045 |
| `r15-probe` stack | `iac/tofu/stacks/r15-probe/` | Two throwaway clones, `r15-probe-lxc-runner-v<N>` and `r15-probe-vm-docker-v<N>`, that carry the runner-class firewall policy for the isolation proof | ADR 0031, 0044 |
| `guest` stack | `iac/tofu/stacks/guest/` | Guests sized by a cloud flavor, read from `guests.yml`; created by `scripts/iac/new-guest.sh` | ADR 0055 |
| Runner-class policy | `iac/policy/runner-class.yml` | Per-guest firewall options and the security group every runner guest gets | ADR 0027 |
| Build-cache client | `scripts/ci/build_cache/` | Layered cache client (domain, application, adapters); `tests/cache/test_dependency_rule.py` fails on an inward-pointing violation | ADR 0049 |
| Reusable pipeline | `.github/workflows/reusable-sdet-pipeline.yml`, `.github/actions/build-cache/` | Build and test jobs with restore steps; save jobs only in environment `cache-writer` | ADR 0049, 0050 |
| Evidence tooling | `scripts/evidence/publish.py` | Publishes sanitized transcripts with a hash index and checks them | ADR 0052 |

## Trust boundaries

| Boundary | Inside | Outside | Enforced by |
|---|---|---|---|
| Workstation | The operator, every local administrator, the age key, the VM disk | Everything on the network | Operating-system accounts; Hyper-V Administrators membership is an accepted widening (D43, Hyper-V Administrators re-confirmed) |
| Switch port | The PVE VM | The workstation, its VPN-routed prefixes, peers, the home LAN | Hyper-V port ACLs plus a Windows firewall rule; row 42 (ACL read-back) |
| PVE host | Root on pve01, the root orchestrator | Guests, tokens | Classic PVE firewall, SSH key-only access, sandboxed guest step |
| Guest vnet `guests` | Runner-class guests (untrusted code from a public repository) | Management, host, peers, other guests | Port isolation, per-guest firewall with `policy_out DROP`, group `guest-egress`, guard |
| Cache vnet `cache` | `build-cache-debian-13` | Everything except one tcp path from runners | Group `cache-ingress`, one first-line rule in `guest-egress` |
| Template pool | Templates only | The provisioner token may clone, not modify | Pool `templates`, role `HomelabTemplateClone` |

## Networks

| Network | Range | Notes |
|---|---|---|
| Management (Hyper-V internal switch) | `10.99.0.0/24`: host `.1`, pve01 `.2` | The only path to PVE; the web UI is reached through the host and PVE stays off the mesh VPN (ADR 0006, 0008) |
| Guests | `10.99.16.0/24`, gateway `.1`, zone `hlab`, vnet `guests`, `isolate_ports` | Static addresses, no DHCP; source-NAT to the management address; guest to guest unreachable even with the firewall stopped (row 51, red-first isolation; ADR 0030) |
| Cache | `10.99.17.0/24`, gateway `.1`, vnet `cache`; the cache container at `10.99.17.10:8080` | Forwarding on; SNAT only `-s 10.99.17.0/24 -o vmbr0`, so runner-to-cache traffic keeps the runner's address (row 61, cache network; ADR 0045) |

Firewall objects: ipsets `management`, `public-v4` and `host-routed`; security group `guest-egress` (first line accepts tcp to the cache endpoint, then drops the host-routed and special-use prefixes, then accepts public IPv4); group `cache-ingress` (tcp 8080 from the runner subnet, tcp 22 from the gateway); host traffic only from management (ADR 0027, 0046, 0050). The prefixes the workstation routes elsewhere are read at VM start, kept encrypted in SOPS and never written to the repository in clear.

The guard (`homelab-guest-firewall-guard.timer`) reads each guest through the API against a per-vnet policy rendered from the inventory and stops a non-compliant guest; it never starts one. Behaviour and output: [RUNBOOK.md](../../RUNBOOK.md) 3.6 (ADR 0037, 0047).

Guest addresses and IDs: probes `.21`, `.22`; flavor guests `.101` to `.199` with VMID `9500` plus the slot; the cache container VMID 9050; template blocks 9200 to 9399.

## Identities and tokens

| Identity | Holds | Cannot | Where the secret lives |
|---|---|---|---|
| `root@pam` | Break-glass over an SSH key from the management address only; password login off | Be used by automation | Root password in `iac/secrets/hosts/pve01.sops.yaml`; TOTP enrolment is an open owner step ([limits-and-gaps.md](limits-and-gaps.md)) |
| `automation` (OS user) | Key-only, passwordless sudo | Log in with a password | Public keys in a SOPS file; private keys on the operator side |
| `tofu@pve!provisioner` (token) | Guest lifecycle in pool `homelab`, SDN use on the guest and cache vnets, `VM.Clone` on pool `templates` (row 48, token boundary; row 57, template protection) | Create users (403), delete or retag a template (403), delete a volume | `iac/secrets/tofu/pve01-api.sops.yaml`, written by the role |
| Template root orchestrator | Root on the host, runs `qm`/`pct` with arguments the host chooses | Parse guest output as instructions; the guest-facing step runs as a non-root sandboxed user | None; systemd units on pve01 (ADR 0038) |
| Cache writer `ci-writer` | One htpasswd user on the cache container; the same value as the environment secret `CACHE_WRITER_PASSWORD` in environment `cache-writer` | Anything else; anonymous reads need no credential | `iac/secrets/hosts/pve01-cache.sops.yaml`, written only by `scripts/iac/cache-writer-secret.sh` |
| SOPS age identity | Decrypts every file under `iac/secrets/` (single recipient) | Be recovered if lost | Operator profile plus an off-machine copy held by the owner |
| OpenTofu state passphrase | Encrypts state and plans | | `iac/secrets/tofu/pve01-state.sops.yaml` |
| Controller token (Phase 5) | Does not exist yet | | Design in [next-phases.md](next-phases.md) |

## Data flow: CI job to runner to cache

Built and measured today (hosted runners, cache disabled): every restore step prints `miss (no store configured)` and no job waits on the cache (row 68, hosted run with the cache off).

Designed, measured only from a runner-template clone (row 63, hit ratio over 20 runs; ADR 0053), not from a real runner:

1. A workflow event queues jobs; a router picks the pool or hosted (Phases 5 and 6, not built).
2. The controller (Phase 5, not built) mints a JIT configuration and creates a linked clone of the `current` runner template on the `guests` vnet; the clone inherits the template's tags and guest firewall (row 58, clone inheritance).
3. The runner registers as ephemeral, takes one job and is destroyed.
4. Restore: the client computes keys from lockfile hashes, toolchain, OS, architecture and runner class; it reads the pointer and the blob anonymously from `10.99.17.10:8080`, verifies the digest, extracts only the plan's paths, and restores compiled outputs only on an exact match of the input tree ids (ADR 0049).
5. Build and test run; nothing here holds a credential.
6. Save: only a job on the default branch in environment `cache-writer` runs the client with the writer credential at step level, over artifacts the same run built; the server verifies every blob's sha256 and answers 500 on a mismatch (ADR 0048, 0050).
