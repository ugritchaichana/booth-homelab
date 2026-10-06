# 0021. Keep one inventory file as the single host data source

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D46 in docs/platform/requirements.md (requirement R5.1)

## Context

ADR 0018 makes hosts independent records and says adding a host is a data change. Two tools need the same facts about a host: Ansible (address, user, node name) and OpenTofu (node name, guest network). The retired layout kept a separate Ansible inventory and a separate set of OpenTofu variables, so a host address or subnet had two homes that could disagree. Another consumer, the SSH config renderer, needs the host list too.

## Options considered

1. One OpenTofu root module per host and one Ansible inventory file per host — each host is a directory, so a second host is new code.
2. Ansible inventory and OpenTofu variable files kept in sync by hand — no tooling, but two copies of every address and subnet.
3. One inventory file in Ansible's YAML format, read by Ansible directly and by OpenTofu through `yamldecode(file())`, with one stack type instantiated per host by a `host` variable.

## Decision

Option 3. `iac/inventory/hosts.yml` is the only file that lists hosts and their data (`ansible_host`, `ansible_user`, `pve_node_name`, `management_source`, `guest_network`, `ssh_key_name`). Shared defaults live beside it in `iac/inventory/group_vars/`: `all.yml` for provider-neutral values and `pve_hosts.yml` for Proxmox values.

- Secrets are never in this file. A host's secrets sit in `iac/secrets/hosts/<name>-*.sops.yaml`, found by host name (ADR 0009).
- `scripts/iac/render-ssh-config.sh` and `scripts/iac/ansible.sh` read this file, so they need no change for a second host.
- Adding a host is one new entry here plus its SOPS file.

## Rationale and trade-offs

- A single file removes the disagreement between tools; Ansible's YAML inventory is also plain data that OpenTofu can parse without a plugin.
- Accepted loss: the file must stay within what both parsers read, so host data cannot use Ansible templating (`{{ }}`) in values that OpenTofu consumes.
- Not proven yet: an OpenTofu stack reading this file, and a second host. Until the stack exists the OpenTofu half is HYPOTHESIS.
- Revisit if a host kind needs data that cannot be expressed as plain YAML.
