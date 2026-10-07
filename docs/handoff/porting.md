# Porting to bare-metal Proxmox on-prem

Target: one or more physical servers running Proxmox VE 9, in an on-premises network, replacing the reference setup (a nested Hyper-V guest on a workstation). Statements below that were not measured are marked HYPOTHESIS; the reference tree has no run on any target other than the reference machine, and no non-Proxmox proof exists (R10, portability, is open: Phase 8).

## What to drop

| Drop | Where | Why it goes |
|---|---|---|
| The whole Windows host layer | `scripts/hyperv/` (`New-PveHost.ps1`, `Invoke-PveVm.ps1`, `HomelabHyperV.psm1`, `Test-R15Controls.ps1`, `pve01.psd1`) | It creates and fences the VM; a physical server has no VM, switch, NAT or port ACLs (ADR 0003, 0006, 0007) |
| Windows firewall rule, WinNAT, the checkpoint workflow | same | Host-side isolation layers and restore points of the VM (ADR 0019) |
| The Hyper-V tests and their workflow | `tests/hyperv/`, `.github/workflows/hyperv-ci.yml`, `tests/isolation/test-role-hyperv-guest.sh` | They test the files above |
| The role `hyperv_guest` | `iac/ansible/roles/hyperv_guest/`, included twice in `iac/ansible/playbooks/site.yml` | It blocks `hv_sock` and asserts no Hyper-V integration daemons. The includes are unconditional, so a bare-metal host needs them removed or conditioned on a host variable: this is the one code change in adding a non-Hyper-V host. Leaving it in is probably harmless (HYPOTHESIS, untested) |
| The control path through the Windows host | ADR 0011, ADR 0022 inner hop, the mesh-VPN forward of the web UI (ADR 0008) | They exist because WSL cannot reach the VM's network directly (row 39, WSL path, WSL path); on-prem the operator reaches pve01 over a normal route or a jump host |
| The laptop's RAM and disk budget | D19 (resource budget, revised); rows 28 and 29 (RAM and disk headroom) | Sized for a daily-use workstation |
| The workstation-reboot and standby caveats | row 43 (converge run) | Laptop behaviour |
| Nested virtualization requirements | D9 (Docker workloads); rows 12 and 36 (nested KVM) | Containers and VMs run on the physical CPU's virtualization directly |

## What carries over unchanged

| Item | Where | Evidence it works |
|---|---|---|
| Host baseline, API identity, firewall, templates and cache roles | `iac/ansible/roles/{base,pve_host,pve_api_identity,pve_firewall,pve_templates,cache_service}` | Rows 43 (converge), 48 (token boundary), 55 (template builds), 62 (cache API) |
| OpenTofu stacks and modules (SDN, flavors, template source, guests, cache, probe) | `iac/tofu/` | Rows 49 (state), 50 (guest network), 61 (cache network) |
| Inventory model and per-host SOPS files | `iac/inventory/`, `iac/secrets/` | ADR 0021, 0033 |
| Templates (both classes), the orchestrator, versioning and rollback | `iac/ansible/roles/pve_templates/`, `iac/policy/runner-class.yml` | Row 56 (retention and rollback) |
| Cache service, client and workflow wiring | `scripts/ci/build_cache/`, `.github/` | Row 62 (cache API), row 68 (hosted run) |
| Guard and per-vnet policy | `pve_firewall` role | ADR 0047 |
| Test suites and evidence tooling | `tests/`, `scripts/evidence/` | [testing.md](testing.md) |
| Decisions | [ADR index](../adr/README.md) | [decisions.md](decisions.md) |

The operator toolchain (WSL on the reference setup) is a Linux shell with pinned tools; any Linux operator machine works (ADR 0010, HYPOTHESIS for non-WSL).

## What must change (data, not code)

| Item | Reference value | On-prem work |
|---|---|---|
| Management network and `management_source` | The Hyper-V internal switch, host `.1`, pve01 `.2`, SNAT to the PVE address | The server's real management network; the address the operator connects from; SNAT source becomes the uplink address (ADR 0030) |
| Range for guests and cache | `10.99.16.0/24`, `10.99.17.0/24` inside `10.99.0.0/16`, chosen because nothing on the laptop overlapped (D22, Hyper-V NAT subnet) | Re-check overlap with on-prem ranges before choosing; the SDN module refuses ranges overlapping management |
| Host-routed prefixes (`host-routed` ipset) | The prefixes the laptop's VPN routes, read from the host at each VM start, kept encrypted | The on-prem private ranges and any routed prefix runners must not reach, stored per host in `pve01-network`-style SOPS files; on-prem is mostly private space, so the deny-then-allow order in `guest-egress` and the two-half public set (ADR 0027) need review (HYPOTHESIS) |
| Install | Prepared 9.1-1 ISO because 9.2 failed on Hyper-V Gen2 (row 11, 9.2 installer fails on Hyper-V) | The newer installer may work on physical hardware; re-check, keep the answer file and the unattended path (ADR 0004) |
| Storage | ext4 on LVM-thin, left as installed (ADR 0035) | Revisit with real disks; ZFS was rejected only for ARC memory on a 20 GiB VM |
| Flavors and sizes | Catalog entries sized for the laptop budget; the `guest` stack caps one guest at the whole reference VM (`guest_budget`) | Add flavors in `iac/tofu/flavors.json` and raise `guest_budget` for a bigger host; an example entry is in [examples.md](examples.md) (ADR 0017, 0055) |
| Thresholds | Build space guard placeholders (70%, 70%, 8 GiB) | Measure on the target pool |
| Names | `pve01`, `build-cache-debian-13` (inventory alias `build-cache`), VMID blocks 9050, 9100s, 9200s, 9300s, 9500s | Keep or change in the inventory and role defaults; the guard and the template resolver depend on the blocks (ADR 0044) |
| Repository slug and cache URL | The reusable pipeline compares `github.repository` with the reference repository in three places: the top-level `env` values `CACHE_URL` and `BUILD_CACHE_RUNNER_CLASS` (`.github/workflows/reusable-sdet-pipeline.yml:58-59`) and the `HOSTED` value of the `select-runner` job (`:76`). `CACHE_URL` also holds the cache address | Replace the slug in all three with `<owner>/<repository>` of the fork and the address with the fork's cache endpoint; until then a fork silently runs on hosted runners with the cache off |

## What must be re-measured

| Measurement | Why |
|---|---|
| R15 in full: red first, paired controls, baseline, container restart, PVE reboot, host reboot | The proof is about the target network; the Windows-side controls become "reach the same target from a management host" (ADR 0031). The two rows never measured on the reference setup get a positive control here or stay open |
| IPv6 | The reference host had no IPv6 route, accept_ra and autoconf are off and guests have no IPv6 (row 38, host-side layer; row 50, guest network); an on-prem network may offer IPv6 |
| Guest-to-cache path and the first rule of `guest-egress` | Same vnets, different uplink; confirm runner-to-cache traffic keeps the runner's address (row 61, cache network) |
| Template build times, cache hit ratio, reboot times | All numbers in [results.md](results.md) are laptop numbers |
| The VM class on real KVM | Row 36 (nested KVM) and row 59 (clone isolation) were measured nested; re-run the VM-clone checks: container runs, no virtualization flags exposed, no Docker TCP listener |
| Thin-pool and storage headroom | The reference pool was 62.5 GiB (row 56, retention; requirements.md section 7.2a) |
| Converge with reboots | The pool-drain gate matters more with several physical hosts ([operations.md](operations.md)) |

## Several hosts

Hosts are independent, not a cluster (ADR 0018). Per [operations.md](operations.md): an inventory entry, the per-host SOPS files, a re-rendered SSH config, `var.host` for the stacks, templates built per host, R15 re-run per host. Template builds and the cache are per host; sharing a cache across hosts is not designed (a cache per host is what exists; ADR 0045 places it on the host's own routed vnet).

## Portability proof (not done)

R10 (portable to VPS, on-prem and other hosts) requires a run showing the same roles converging on a hosted Ubuntu VM and a runner registered from there running a job green; a Windows-subsystem Debian does not count. Phase 8 owns it ([next-phases.md](next-phases.md)). R10 names the runner, cache and controller roles, the controller core and the workflows as the provider-neutral parts; the Proxmox roles need Proxmox by definition. Whether `cache_service` converges outside the container it was built for is untested (HYPOTHESIS).
