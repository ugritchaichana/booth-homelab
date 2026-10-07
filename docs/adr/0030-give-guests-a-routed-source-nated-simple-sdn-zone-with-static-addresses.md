# 0030. Give guests a routed, source-NATed simple SDN zone with static addresses

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D54 in docs/platform/requirements.md

## Context

Guests need a network that reaches the internet through the host only and cannot see the management network `10.99.0.0/24` (ADR 0006). The host has no SDN objects yet, `dnsmasq` is not installed and `libpve-network-perl` is 1.6.7 (`host-facts` section "sdn and dnsmasq"). The firewall files belong to Ansible and the per-guest firewall options to the guest changes (ADR 0025), so this change owns only the network objects.

## Options considered

1. A hand-made bridge in `/etc/network/interfaces` with a masquerade rule — no SDN dependency, but a second writer to files Ansible owns and nothing OpenTofu can plan.
2. An SDN simple zone with a vnet, a subnet with SNAT and DHCP through `dnsmasq` — leases and DNS for free, but a new package and a new listener on the host.
3. An SDN simple zone with a vnet, a subnet with SNAT, static addresses and no DHCP — all objects are API resources, nothing new listens on the host.

## Decision

Option 3, in `iac/tofu/modules/proxmox/sdn/`, called by `iac/tofu/stacks/proxmox-host/main.tf` from the host's `guest_network` entry in the inventory.

- Zone `hlab`, vnet `guests`, subnet `10.99.16.0/24`, gateway `10.99.16.1` for the first host (`iac/inventory/hosts.yml`).
- `isolate_ports = true` on the vnet (`main.tf:20`) and `snat = true` on the subnet (`main.tf:27`). No DHCP range and no zone `dhcp` backend.
- Guests take a static address and resolver (a public resolver, set per guest by the guest changes). The zone `dns` attribute is a PowerDNS API address, not a resolver, and stays unset.
- The module rejects a subnet that is not an IPv4 network address of /16 to /28, a gateway outside the subnet, and any overlap with `10.99.0.0/24` or with `reserved_cidrs` (`variables.tf:35-64`).
- The provider's `proxmox_sdn_applier` runs the SDN apply, replaced whenever the zone, vnet or subnet changes (`main.tf:31-45`); a second applier destroyed last applies deletions (`main.tf:48`).
- A second host is an inventory entry; `tests/two_hosts.tftest.hcl` plans a fixture host with no code change.

## Rationale and trade-offs

- Option 3 adds no package and no new socket, but the zone adds host addresses, `10.99.16.1` and a link-local one on the `guests` bridge, where the existing wildcard listeners answer, among them sshd 22, rpcbind 111 (tcp and udp), spiceproxy 3128 and pveproxy 8006. It also turns on IPv4 forwarding. Only the host firewall's management-only input policy (ADR 0027) keeps guests off those listeners, and the R15 isolation probe measures it. Option 2 would add a package and a listener for leases that static addresses make unnecessary.
- Accepted loss: every guest address is assigned by hand and must be unique; nothing detects a duplicate. Revisit when guests are created from templates in bulk.
- Measured offline with a mocked provider: `tofu test` passes the policy, two-host and overlap cases, and removing the overlap check or setting `snat` or `isolate_ports` to false each makes a test fail.
- HYPOTHESIS, proven only by the host apply: SNAT works with the firewall on; `proxmox_sdn_applier` is documented EXPERIMENTAL and a second plan after apply shows no changes; the pinned provider's `isolate_ports` takes effect on the bridge.
- Measured on the host: the zone's NAT rule is `-j SNAT --to-source`, so the zone uses source NAT and not masquerade; the title says so.
