# OpenTofu

| Path | Purpose |
|---|---|
| `stacks/proxmox-host/` | The host root module; `var.host` selects an inventory entry, so another host is data, not code. Run it through the wrapper `scripts/iac/tofu.sh` (see its README). |
| `stacks/r15-probe/` | Throwaway container and VM that carry the guest firewall policy for the R15 isolation proof; applied only during the proof and destroyed after it (ADR 0031). |
| `modules/proxmox/sdn/` | The guest network: a simple SDN zone, a vnet with `isolate_ports`, and a subnet with SNAT, static addressing and no DHCP (ADR 0030). |
| `flavors.json` | Instance flavor catalog kept for the runner work of Phase 3; nothing reads it yet. |

Provider-specific code stays under `modules/<provider>/`; stacks call it with values from `iac/inventory/hosts.yml`.

## Guest network

The stack reads `guest_network` (`zone`, `vnet`, `cidr`, `gateway`) of the selected host. The module refuses a subnet that overlaps the management network `10.99.0.0/24`, is not an IPv4 /16 to /28 network, or leaves the gateway outside it. It runs the SDN apply through `proxmox_sdn_applier`, an experimental provider resource. Guest firewall options and guest DNS belong to the guest changes (ADR 0025).

## Checks without a host

The stack's state encryption needs a passphrase of at least 32 characters for `test`; use a throwaway one:

```sh
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123
tofu fmt -check -recursive iac/tofu
(cd iac/tofu/stacks && tflint --recursive --config "$PWD/../../../.tflint.hcl")
tofu -chdir=iac/tofu/stacks/proxmox-host init -backend=false
tofu -chdir=iac/tofu/stacks/proxmox-host test
```

`tests/` holds `tofu test` files with a mocked provider: policy of the network objects, the overlap and range rejections, and a two-host plan from `tests/fixtures/hosts.yml`.

CI finds root modules by layout, so a new stack is a new directory under `stacks/`. Per-guest firewall options and rules belong to the stack that creates the guest (ADR 0025).
