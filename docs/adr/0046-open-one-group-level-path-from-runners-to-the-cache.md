# 0046. Open one group-level path from runners to the cache

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D74 in docs/platform/requirements.md
- Refines: ADR 0027

## Context

Runner guests carry policy `DROP` in and out and one rule, the `guest-egress` group (ADR 0027). The group accepts only public addresses, so a runner cannot reach the cache at `10.99.17.10`, and the guard (ADR 0037) stops any guest with a rule beyond the group.

## Options considered

1. A per-guest rule on every runner — the guard would have to allow it, and every clone would carry its own copy.
2. Widen the public set to include the lab ranges — opens the host, the management network and the other guests.
3. One accept line in the `guest-egress` group, first, for the cache address and port only, plus a new group `cache-ingress` for the cache container.

## Decision

Option 3, rendered from inventory by `iac/ansible/roles/pve_firewall/templates/cluster.fw.j2`.

- `guest-egress` gains `OUT ACCEPT -dest <cache address> -p tcp -dport <cache port>` as its first line. Nothing is rendered when the host has no `cache_endpoint`.
- `cache-ingress` holds `IN ACCEPT -source <guests cidr> -p tcp -dport <cache port>` and `IN ACCEPT -source <cache gateway> -p tcp -dport 22`. The cache container carries `guest-egress` and `cache-ingress`.
- Runners keep one group rule, so the guard sees no new rule shape on them.

## Rationale and trade-offs

- One address and one port leave the runner group open, so what a runner can reach grows by exactly one tcp port on one address.
- The cache port is reachable from every runner. Runners are untrusted, so the store must not trust a request because it came from the guests subnet; authorising cache entries belongs to the store, not to this rule.
- tcp/22 to the cache is open only from the cache gateway (the host), so a runner cannot reach it. The R15 probe measures that with a paired positive on the cache port (`cache_ssh_blocked` against `cache_port_reachable`).
- The cache address is not in `host-routed`, so the first-line placement is for clarity and for safety against a later drop rule. The render test pins the order.
- Changing the address or port is an inventory change and one Ansible run behind the dead-man of ADR 0027.
