# 0037. Make the guest firewall guard reject extra enabled rules on vnet guests

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D65 in docs/platform/requirements.md
- Refines: ADR 0026, ADR 0027

## Context

ADR 0026 accepts that the provisioner token can change a guest's firewall rules, because `VM.Config.Network` has no finer split, and relies on the root-owned guard of ADR 0027 to detect drift. The guard required the firewall enabled, `policy_in DROP`, `policy_out DROP`, `ipfilter` on, `firewall=1` on every NIC and an enabled `guest-egress` group rule. It never looked at any other rule, so a rule such as `OUT ACCEPT` added beside the group rule, or an `IN ACCEPT` from anywhere, passed every check: with the policies at `DROP`, an explicit accept rule opens exactly the path the group exists to close. The sentence "the guard detects drift" was therefore not true for the one change the token can make.

The R15 probe guests legitimately carry a second rule: an enabled `IN ACCEPT tcp/22` whose source is the vnet gateway (the host), declared in `iac/tofu/stacks/r15-probe/main.tf`. Template build guests will carry the same rule while they are built.

## Options considered

1. Leave the guard as it is — the token can open egress and nothing stops the guest.
2. Reject every enabled rule except the group rule — closes the gap but stops the probe guests that need the host's SSH rule, and the build guests later.
3. Reject every enabled rule outside a fixed allowed set: the `guest-egress` group rule and one `IN ACCEPT tcp/22` from the vnet gateway, nothing else qualified on that rule. Disabled rules are ignored.

## Decision

Option 3, in `iac/ansible/roles/pve_firewall/files/guest-firewall-guard.py`.

- A guest with a NIC on the guest vnet is a violation, handled like every other violation (marker file, journal line naming the rule position, guest stopped when running), when it has an enabled rule that is neither the `guest-egress` group rule nor the gateway SSH rule. The gateway SSH rule matches only with type `in`, action `ACCEPT`, protocol `tcp`, destination port `22`, source equal to the gateway, and no destination, source port, macro or interface qualifier.
- The gateway comes from a new required guard argument `--gateway`, which the role passes from `guest_network.gateway` of the inventory. The role asserts it is a single IPv4 address before installing the unit, so an empty value fails the converge instead of rendering an argument with no operand.
- Guests with no NIC on the guest vnet are unchanged: the guard still does not examine them. Examining other bridges is a Phase 4 decision, taken together with where the cache service sits.

## Rationale and trade-offs

- The guard cannot tell a template build guest from a probe guest or a runner clone, so the gateway SSH rule is allowed on every vnet guest at all times. The source is the host itself and the vnet ports are isolated, so no other guest can use that rule; the residual is that a runner clone which inherited the build rule is not flagged. The planned template build pipeline strips that rule before conversion, and the host proof of that pipeline checks that clones do not inherit it.
- The change only adds a way to fail. A guest that passed before can now be stopped, so a guest that carries an undeclared enabled rule today is stopped on the first run after the converge. The run that installs the unit requires a clean guard result, so the converge reports it.
- Unchanged: the detection window of up to a minute plus the run time, and the rule that the guard never starts anything.
- The offline test `tests/isolation/test-guest-fw-guard.sh` pins the cases: an extra `OUT ACCEPT` beside the group, an extra `IN ACCEPT` from anywhere and an inbound `tcp/22` from another source each stop the guest; the gateway SSH rule and a disabled extra rule leave it alone; a guest off the vnet with an extra rule is still ignored.
