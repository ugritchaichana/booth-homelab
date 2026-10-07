# 0047. Give the guest firewall guard a per-vnet policy

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D75 in docs/platform/requirements.md
- Amends: ADR 0037

## Context

The guard took one vnet, one group and one gateway and ignored every guest with no NIC on that vnet. With the cache on a second vnet (ADR 0045) that left two gaps: the cache container needs a different group set, and a guest on any other bridge, `vmbr0` included, was never examined. ADR 0037 deferred the second gap to Phase 4.

## Options considered

1. More flags per vnet — the command line grows with every vnet and cannot say "no gateway rule".
2. Keep the single vnet and leave the cache container unguarded — the one guest every runner talks to would be the one nobody checks.
3. A policy file, rendered by Ansible from inventory, with an entry per vnet.

## Decision

Option 3: `--vnet`, `--group` and `--gateway` are replaced by `--policy FILE`. The file is `/etc/homelab/guest-firewall-guard-policy.json`, for example `{"vnets": {"guests": {"groups": ["guest-egress"], "allow_gateway_ssh": "10.99.16.1"}, "cache": {"groups": ["guest-egress", "cache-ingress"], "allow_gateway_ssh": null}}}`.

- A guest with no NIC is ignored.
- A guest with any NIC on a bridge that is not a key of the table is a violation, handled like every other one (marker, journal line, stopped when running). Any guest the host runs on `vmbr0` is therefore stopped by the first run after the change.
- On known vnets the checks of ADR 0037 stay: firewall enabled, `policy_in` and `policy_out` DROP, `ipfilter`, `firewall=1` on every NIC. Every required group of the vnet must be present and enabled, and any enabled rule outside the required groups and the vnet's gateway SSH rule (when set) is a violation. A guest on several vnets must satisfy the union of their groups.
- An unreadable or malformed policy file exits 4 and stops nothing, like an unreadable guest list. Exit codes, lock, markers and unverified counting are unchanged.
- A compliant template, running or not, produces no violation and no journal line; a non-compliant stopped guest still repeats its line each run.

## Rationale and trade-offs

- The group content is not expanded: the guard trusts the group name, and the cluster file (Ansible-owned, dead-man protected) owns what the group allows.
- The cache vnet allows no gateway SSH rule at guest level, because `cache-ingress` already holds the host's tcp/22 rule at group level.
- A guest on an unknown bridge is stopped even when its own firewall is perfect, because the guard cannot know what that bridge reaches. The runbook lists guests on `vmbr0` before the converge.
- The offline test `tests/isolation/test-guest-fw-guard.sh` pins the cases: unknown bridge stopped, cache guest without `cache-ingress` stopped, cache guest with an extra rule stopped, compliant cache guest and compliant stopped template left alone.
