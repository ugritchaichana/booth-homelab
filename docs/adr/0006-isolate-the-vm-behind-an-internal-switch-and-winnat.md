# 0006. Isolate the VM behind an internal switch and WinNAT

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D7, D22, D35 in docs/platform/requirements.md

## Context

The Proxmox VM needs outbound internet and a stable address for management. The workstation has one uplink, Wi-Fi (measured 2026-10-06), and no NAT object existed. The host also carries other private networks (a host VPN routing seven private prefixes, a tailnet, the home LAN, the WSL subnet), so the VM's network position decides what code running on it could reach (ADR 0007).

The guest address range must not overlap any route or address on the host. Measured 2026-10-06: `10.99.0.0/16` overlaps none of them and no NAT object existed.

## Options considered

1. External switch bound to the Wi-Fi adapter — the VM gets a LAN address; bridging a Wi-Fi client needs MAC handling that was unproven here (HYPOTHESIS), and it puts the VM directly on the home LAN.
2. Hyper-V Default Switch — zero setup; its address range is assigned by Windows and changes between boots, so a static guest address and a NAT-bound firewall rule would drift.
3. Internal switch plus WinNAT with a static range — no dependency on Wi-Fi bridging; fixed addresses; the host stays the single gateway and a place to enforce rules.

## Decision

Create an internal switch and a `New-NetNat` object named `homelab-pve01` on `10.99.0.0/24` (`scripts/hyperv/pve01.psd1:10-12`, `New-PveHost.ps1:363`): host `10.99.0.1`, PVE `10.99.0.2` with a static address and a static MAC. Bridges inside PVE stay within `10.99.0.0/16`. MAC address spoofing is off, DHCP guard and router guard are on (`New-PveHost.ps1:384`), automatic checkpoints are off. There is no port mapping and no new listener on the host. Guests inside PVE sit on a routed, masqueraded PVE bridge, so every guest packet reaches Hyper-V with PVE's own address.

## Rationale and trade-offs

- NAT works over Wi-Fi without bridging and gives a fixed range to write rules against. The operator chose the range (D22) because the measured routes and addresses leave it free, and re-checked the routes before the setup script ran.
- With spoofing off, Hyper-V drops frames from MAC addresses other than the adapter's. Containers or VMs inside PVE must therefore be routed or NATed by PVE, not bridged with their own MACs (`scripts/hyperv/README.md:122`). Accepted cost: bridged guests with their own MACs are not supported on this VM.
- The host reaches the guest directly; WSL does not (measured: TCP 22 from WSL times out, path via the Windows SSH client works; see ADR 0011).
- Accepted cost: the guest has no inbound reachability from the LAN and depends on the host being awake. That is intended for a lab that overflows to hosted runners when the VM is stopped.
- Revisit if the uplink becomes wired or the platform moves to a host where an external switch is reliable.
