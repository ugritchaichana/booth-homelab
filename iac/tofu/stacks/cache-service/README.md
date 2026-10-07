# cache-service stack

The unprivileged container that hosts the build cache (ADR 0048). The service itself is installed by the Ansible role `cache_service` (`iac/ansible/playbooks/cache.yml`). State handling, secrets and the API forward are the same as the `proxmox-host` stack's; the wrapper is `scripts/iac/tofu.sh cache-service <host> <tofu args>` and the state passphrase is the host's.

## What it declares

| Object | Value |
|---|---|
| Container | id 9050 (variable `vm_id`, validated outside the template blocks and the probe ids), pool `homelab`, unprivileged, `start_on_boot`, created stopped and `ignore_changes = [started]`: `cache.yml` starts it after reading the firewall back |
| Source | the Debian 13 standard template the template role fetches (read from `pve_templates_classes` in the role defaults), not a clone |
| Size | 1 core, 1024 MB, no swap, root 4 GiB, mount point `mp0` of 10 GiB at the role's data mount, both on `local-lvm` |
| NIC | `eth0` on the `cache` vnet, firewall flag on, static address and gateway from `cache_endpoint` and `cache_network` of the host entry in `iac/inventory/hosts.yml` |
| Firewall options | the runner-class values of `iac/policy/runner-class.yml` (enable, DROP in and out, ipfilter, macfilter, dhcp 0, radv 0) |
| Firewall rules | exactly two group rules: `guest-egress` (read from the policy) and `cache-ingress` |
| Root key | the ed25519 public keys of `ssh_public_keys`; never a private key |

The security groups are created by the `pve_firewall` role, so run `site.yml` first. The host entry must carry `cache_network` and `cache_endpoint`; without them the plan stops at a precondition. A precondition also stops the plan when the cache limit of the role (`cache_service_max_size_gib`) is above 80 percent of `data_disk_gb`, or when the address is the gateway or outside the subnet.

The API token needs `SDN.Use` on the `cache` vnet path; that grant belongs to the identity role and is not declared here.

## Run

```sh
export TF_VAR_ssh_public_keys='["ssh-ed25519 AAAA... automation"]'
bash scripts/iac/tofu.sh cache-service pve01 init
bash scripts/iac/tofu.sh cache-service pve01 apply
```

## Checks without a host

```sh
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123
tofu -chdir=iac/tofu/stacks/cache-service init -backend=false
tofu -chdir=iac/tofu/stacks/cache-service validate
tofu -chdir=iac/tofu/stacks/cache-service test
```

`tests/cache.tftest.hcl` reads `tests/fixtures/hosts.yml` and asserts the shape with literal values: the NIC, address, size, template, mount point, reserved ids, firewall options and the exact two rule groups. It also rejects a private key, an id inside a template block, a data volume the cache limit does not fit, a host without the cache keys and the gateway as the address.
