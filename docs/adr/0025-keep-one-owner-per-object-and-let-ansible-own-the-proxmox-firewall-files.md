# 0025. Keep one owner per object and let Ansible own the Proxmox firewall files

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D47 in docs/platform/requirements.md

## Context

Ansible and OpenTofu both can write Proxmox objects. Two writers on one object produce drift that neither run reports. The firewall is the object where that matters most: it is the control that isolates the guests (R15).

Measured on the PVE VM (9.2.21) from the apidoc the host ships: creating a cluster security group or ipset (`POST /cluster/firewall/groups`, `POST /cluster/firewall/ipset`) requires `Sys.Modify` on `/`; node firewall rules require `Sys.Modify` on `/nodes/{node}`; guest firewall rules require only `VM.Config.Network` on the guest. Guest firewall policy is read from the guest's own file, defaulting to `policy_in DROP` and `policy_out ACCEPT` (`src/PVE/Firewall.pm:2971-2973`, upstream master read 2026-10-07; the installed 9.2 copy was not diffed, HYPOTHESIS that it matches).

## Options considered

1. OpenTofu owns the cluster and host firewall through the provider's cluster-firewall resources — one tool for every Proxmox object, but its token needs `Sys.Modify` on `/`, which lets the identity that creates guests rewrite the rules that confine them.
2. Ansible owns the `cluster.fw` and `host.fw` files, OpenTofu owns guests — the token stays narrow; two tools touch the firewall (files, API) but never the same file.
3. Edit the firewall in the web console — nothing to review, nothing to restore.

## Decision

Option 2.

- Ansible owns: operating-system configuration, its own SSH identity (ADR 0023), OpenTofu's API identity (ADR 0026), and `/etc/pve/firewall/cluster.fw` and `/etc/pve/nodes/<node>/host.fw` (ADR 0027).
- OpenTofu owns: SDN, guests, the firewall attachment on each guest NIC, each guest's own firewall options and rules (policy, ipfilter, logging, the rules that reference the security group), and template downloads.
- A guest option such as `policy_out DROP` is a per-guest file, not a cluster default, so it belongs to the guest definition in OpenTofu, not to the firewall role. The guest network and R15 probe pull requests own the per-guest options and the check that detects their drift; this change checks only the cluster and host files.

## Rationale and trade-offs

- The earlier hypothesis that cluster firewall endpoints need `Sys.Modify` on `/` is confirmed for groups and ipsets; keeping them out of OpenTofu is what lets its token omit `Sys.Modify`.
- Requirement R4 says OpenTofu declares users, tokens and ACLs. This is met for OpenTofu's guests only; the identity OpenTofu itself uses is Ansible-owned (ADR 0026). Recorded as a deviation.
- Accepted loss: a firewall change is an Ansible run behind a dead-man, not a plan with a diff in the provider. The role compares the rendered file with the live one and reports `changed=0` when equal.
- Revisit if the provider gains a narrower permission for cluster firewall writes, or if a second host makes per-file templating awkward.
