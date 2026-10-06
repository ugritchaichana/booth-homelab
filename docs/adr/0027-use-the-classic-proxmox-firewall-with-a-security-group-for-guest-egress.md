# 0027. Use the classic Proxmox firewall with a security group for guest egress

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D53 in docs/platform/requirements.md

## Context

Guests must reach public IPv4 only: no private, shared, link-local, multicast or reserved range, no prefix the workstation routes elsewhere (R15), and no path to the host's own services except from the management source. The control path from the workstation is an SSH `-W` hop whose inner connection starts on the VM itself.

## Options considered

1. Classic `pve-firewall` (iptables, ipset) with a cluster security group — supported, files under `/etc/pve`, rules reviewed as text.
2. The nftables `proxmox-firewall` — the Proxmox documentation calls it a technology preview, not suited for production use.
3. Hand-written nftables — full control, but it competes with the rules `pve-firewall` writes into the same chains.

## Decision

Option 1, rendered by `iac/ansible/roles/pve_firewall`.

- `cluster.fw`: `enable: 1`, `policy_in DROP`; ipset `management` holding the management source; alias `local_network` pinned to the same address; ipset `host-routed` holding the prefixes from `iac/secrets/hosts/<host>-network.sops.yaml`; ipset `public-v4` of `0.0.0.0/1` and `128.0.0.0/1` minus `!` entries for `0.0.0.0/8`, `10.0.0.0/8`, `100.64.0.0/10`, `169.254.0.0/16`, `172.16.0.0/12`, `192.168.0.0/16`, `224.0.0.0/4` and `240.0.0.0/4`; group `guest-egress` with `OUT DROP -dest +dc/host-routed -log info` then `OUT ACCEPT -dest +dc/public-v4`. A guest's own file sets its policies and references the group (ADR 0025).
- `host.fw`: `enable: 1`, `nftables: 0`, `log_level_in: info`. No inbound rules are written.
- Dead-man: before the first write the role stores the current files, arms `systemd-run --on-active=<minutes>min --unit=homelab-deadman-firewall` and an enabled boot unit, writes `host.fw` and then `cluster.fw`, and only after the checks below removes the marker and cancels the timer. The restore script puts the previous files back (or deletes new ones), restarts `pve-firewall`, and stops it if any step failed.
- Checks before the cancel: `pve-firewall status` is `enabled/running` with no pending change; `pve-firewall compile` prints no skipped or rejected line; the kernel `management` ipset holds exactly the intended members and `host-routed` the intended number; the inbound chain has the management rules for 22 and 8006 and no other rule for them; `ipset test` rejects sample addresses in every denied range and accepts public ones; a fresh automation login through the control path works.

## Rationale and trade-offs

- Read from upstream `src/PVE/Firewall.pm` (master, 2026-10-07; installed 9.2 not diffed, HYPOTHESIS that it matches): `0.0.0.0/0` is rejected as an ipset entry (`:3735-3752`), hence the two halves with `nomatch` entries; `+name` is valid only in rule address lists (`:2356`), hence a separate `host-routed` ipset and a rule, and `+dc/` so a guest cannot shadow the set; `management` always gains the auto-detected local network (`:4408`), hence the pinned alias (the host detected its own `/24`, measured with `pve-firewall localnet`); built-in rules open 8006, 22, 5900-5999, 3128 and 60000-60050 to `management` and cannot be removed (`:3103-3113`), so the host accepts those from the management source only.
- Control path: `-i lo -j ACCEPT` is the first rule of the host input chain (`:3059`) and `ip route get` for the VM's own address returned `local ... dev lo` (measured on the VM), so the inner hop passes; the outer hop arrives from the management source. The real proof is the fresh login after the change.
- Measured on the VM: iptables 1.8.11 (legacy), ipset 7.22.
- Not measured, proven at the first converge: that the kernel treats a `nomatch` entry inside a covering network as outside the set (the `ipset test` checks assert it); that the enabled firewall leaves SDN source NAT working (Phase 2 probe).
- Named gaps: the domain allowlist (criterion 1.5a) is Phase 5; IPv6 egress is dropped by the guests' default policy, not allowed by a rule; the extra management ports above stay open to the management source.
