# 0008. Keep Proxmox off the tailnet and reach the UI through the host

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D20, D24, D45 in docs/platform/requirements.md

## Context

The owner wants the Proxmox web UI from any of the owner's tailnet devices (D45, "from any machine"). Initially the operator and owner used the laptop only (D24), with no new listener on Windows.

The VM runs untrusted public-repo code behind a host-side isolation layer (ADR 0007). Any tailnet interface inside PVE gives a guest a route into the tailnet, which R15 forbids. The port ACL admits inbound `:22` and `:8006` only from the host address `10.99.0.1`, so anything that must reach the UI has to dial from that address.

## Options considered

1. Tailscale inside PVE (how the retired host was reached) — direct access; adds a tailnet route reachable from guests and one more rule to prove.
2. The Windows host as a subnet router for `10.99.0.0/24` — no relay process; advertises a route for the whole subnet, needs admin-console approval and IP forwarding on Windows, and the ACL would admit it only if the host translated the source address.
3. `tailscale serve` on the Windows host, a TCP forward of tailnet port 8006 — one port, no route, PVE keeps its own TLS end to end; its forward to `10.99.0.2` was untested for a non-loopback target.

## Decision

PVE stays off the tailnet (D20); shell access goes through the Windows host (ADR 0011). For the web UI, chain two hops on the Windows host: `tailscale serve` forwards tailnet TCP port 8006 to `tcp://127.0.0.1:18006`, and a `netsh interface portproxy` rule on `127.0.0.1:18006` relays to `10.99.0.2:8006`. No subnet route is advertised. The UI is reachable only from the owner's tailnet devices, and the browser sees PVE's own certificate.

## Rationale and trade-offs

- Why two hops, measured 2026-10-06 (client 1.102.4): `tailscale serve --tcp 8006 tcp://10.99.0.2:8006` is accepted by the CLI and configured, but carries no traffic. The tailnet port accepts the TCP connection, then the TLS handshake reads 0 bytes. Sampling connections showed the daemon's upstream socket leaving from the Wi-Fi LAN address in `SynSent`, never `Established`, while the browser on the host reached the target from the vSwitch address. A SYN from that address never completing is what the ACL, which admits only the host address, would produce. The cause (the daemon binding to the default interface) is inferred; its logs showed no dial lines.
- A loopback target avoids that leg. A temporary SSH forward proved the shape (same certificate through the tailnet name and directly, HTTP 200); the permanent `portproxy` rule, owned by the IP Helper service, listens on loopback only and persists across reboots. The relay is an ordinary Windows socket, so it follows the routing table to the vSwitch address. Its source address was not sampled; the HTTP 200 shows the ACL admits it. Documentation: https://tailscale.com/kb/1242/tailscale-serve (documents the loopback form only).
- Accepted cost: the UI works only while the workstation is on and the VM runs; two small pieces of Windows configuration exist outside the repository and are not yet codified (a follow-up).
- Recommended before regular remote use: TOTP on `root@pam`. Superseded in part by [ADR 0058](./0058-keep-proxmox-login-hardening-off-in-the-reference-lab.md): off in the reference lab, with the steps for adopters.
- Rollback: `tailscale serve --tcp=8006 off` (or `serve reset`) and `netsh interface portproxy delete v4tov4 listenaddress=127.0.0.1 listenport=18006`.
- Revisit if PVE needs a second remote path (for example runner-controller API calls from another machine).
