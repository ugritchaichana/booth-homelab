# 0007. Enforce a host-side isolation layer with Hyper-V port ACLs

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D37, D17 in docs/platform/requirements.md (derived from R15)

## Context

Runners will execute code from a public repository on a VM whose host is attached to private networks. Measured 2026-10-06: a host VPN routes seven private prefixes, the tailnet adds a route per peer, and the home LAN is reachable over Wi-Fi. A VM behind the host's NAT could reach them unless blocked. Requirement R15 (owner, Q15) says runner code must not reach those networks, the Windows host, or the PVE management interface (`:8006`, `:22`), proven by negative tests that survive host and VM reboots.

Two layers are required. A layer inside PVE is controlled by the thing being isolated, so one layer must sit outside the VM. Whether Windows Defender Firewall filters WinNAT-forwarded traffic was unmeasured, while a Hyper-V port ACL is enforced by the virtual switch.

## Options considered

1. Windows Defender Firewall only — no Hyper-V rights needed; its effect on NAT-forwarded guest traffic was unmeasured (HYPOTHESIS).
2. A firewall inside PVE only — easy to write; enforced by the guest and removable by code that gains root there.
3. Hyper-V extended port ACLs on the VM adapter plus one Defender Firewall rule, on top of the PVE firewall — enforced outside the guest; depends on switch behaviour that had to be measured.

## Decision

Apply Hyper-V extended port ACLs to the VM adapter, built by `Get-PveAclPlan` (`scripts/hyperv/HomelabHyperV.psm1:279-296`) and applied while the adapter is still disconnected; connect it only after the read-back is clean. Larger weight wins:

- Inbound allow, stateful, TCP 22 and 8006, from the host address only; inbound default deny; all IPv6 denied both ways.
- Outbound deny of RFC 1918, `100.64.0.0/10`, link-local, multicast and reserved ranges, plus every prefix the host routes through a non-egress interface. Every such prefix ever seen is kept in a local override outside the repository and stays denied after the VPN disconnects (`HomelabHyperV.psm1:192-206`).
- Outbound allow, stateful, for TCP and for UDP to `0.0.0.0/0`; if a default route exists on another interface, deny all egress (fail closed).
- One inbound Block rule in Windows Defender Firewall for remote `10.99.0.0/24` on the VM's vEthernet (`HomelabHyperV.psm1:453-459`); `Start` refuses without it.

## Rationale and trade-offs

- Measured on this host (probe, 2026-10-06): the switch accepts a stateful rule only for TCP or UDP; ICMP, `ANY` and no protocol are rejected with 0x80070057 when the adapter connects, as is a stateful Deny; weight 65535 is accepted and 100000 rejected. `Add-VMNetworkAdapterExtendedAcl` accepts the bad shapes, so only the connect step proves a rule (`HomelabHyperV.psm1:308-309`). The first install failed closed on this before the VM ever started; the TCP plus UDP pair fixed it (#58).
- Measured from PVE (no runner exists): guest to host ports 445, 135, 139, the home router (80, 53), the host's Wi-Fi, tailnet and mesh addresses and a VPN DNS server are dropped, each paired with Windows reaching the same target; HTTPS and DNS to a public resolver work; IPv6 has no route.
- Known gaps, labelled: (a) NOT MEASURED: the two host-routed prefixes harvested at the time (no host in them was reachable even from Windows), UDP to the host, and WAN reflection through router port-forwards. (b) The two planes were not isolated, so each guest-to-host block proves "at least one layer". (c) ICMP fails by design, which also drops path-MTU signals (HYPOTHESIS: a lower-MTU path can stall TCP; not observed). (d) Hyper-V sockets sit outside both planes. (e) A refresh task that runs `Refresh` on network change is required before any runner registers and does not exist yet (`scripts/hyperv/README.md`, Run it, the note on a scheduled `Refresh` task).
- Accepted cost: Hyper-V Administrators membership lets the owner's processes change the port ACLs (ADR 0014); only the Windows Firewall rule stays outside that reach.
- Revisit when a runner exists: run the negative tests from inside each runner class, before and after reboots.
