# OpenTofu

| Path | Purpose |
|---|---|
| `stacks/proxmox-host/` | The host root module; `var.host` selects an inventory entry, so another host is data, not code. Declares the guest network: the `guests` vnet and, when the host entry has `cache_network`, the `cache` vnet. Run it through the wrapper `scripts/iac/tofu.sh` (see its README). |
| `stacks/cache-service/` | The unprivileged container `cache01` on the `cache` vnet that hosts the build cache; created stopped and started by Ansible after a firewall read-back (ADR 0045, 0048). |
| `stacks/r15-probe/` | Throwaway container and VM, linked clones of the golden templates, that carry the guest firewall policy for the R15 isolation proof; applied only during the proof and destroyed after it (ADR 0031, 0044). Its firewall policy comes from `iac/policy/runner-class.yml`. |
| `modules/proxmox/sdn/` | A simple SDN zone, vnets with `isolate_ports`, and subnets with SNAT, static addressing and no DHCP (ADR 0030, 0045). |
| `modules/proxmox/template-source/` | Resolves a golden template class (`lxc-runner` or `vm-docker`) to the one template that carries the marker, the class and the tag `current` (or a pinned version); the plan stops unless exactly one template in pool `templates` and inside the class VMID block matches (ADR 0044). |
| `modules/flavor/` | Resolves a `provider/instance` flavor name to `cores`, `memory_mb`, `disk_gb` plus ready `vm` and `container` size objects (ADR 0017). Its tests run with the host stack's tests in `stacks/proxmox-host/tests/flavor.tftest.hcl`. |
| `flavors.json` | Instance flavor catalog read by `modules/flavor/`. |

Provider-specific code stays under `modules/<provider>/`; stacks call it with values from `iac/inventory/hosts.yml`. State is local and encrypted per stack and host (ADR 0013, 0051); the wrapper keeps it on the WSL filesystem and each stack's README says where.

## Guest network

The host stack reads `guest_network` (`zone`, `vnet`, `cidr`, `gateway`) and, optionally, `cache_network` of the selected host. The module refuses a subnet that overlaps the management network `10.99.0.0/24`, is not an IPv4 /16 to /28 network, leaves the gateway outside it, or overlaps another vnet. It runs the SDN apply through `proxmox_sdn_applier`, an experimental provider resource. Guest firewall options and guest DNS belong to the stack that creates the guest (ADR 0025).

## Checks without a host

The stack's state encryption needs a passphrase of at least 32 characters for `test`; use a throwaway one:

```sh
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123
tofu fmt -check -recursive iac/tofu
(cd iac/tofu/stacks && tflint --recursive --config "$PWD/../../../.tflint.hcl")
tofu -chdir=iac/tofu/stacks/proxmox-host init -backend=false
tofu -chdir=iac/tofu/stacks/proxmox-host test
```

Repeat the last two lines for `cache-service` and `r15-probe`. Each stack's `tests/` holds `tofu test` files with a mocked provider: the policy of the network objects, the overlap and range rejections, a two-host plan from `tests/fixtures/hosts.yml`, the fail-closed template lookup and the exact firewall groups. `docs/knowledge/test-catalogue.md` lists what each file proves.

CI finds root modules by layout, so a new stack is a new directory under `stacks/`. Per-guest firewall options and rules belong to the stack that creates the guest, except for clones, which inherit them from the template (ADR 0025, 0044).
