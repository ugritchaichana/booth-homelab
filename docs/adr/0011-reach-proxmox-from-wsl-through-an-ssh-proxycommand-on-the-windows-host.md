# 0011. Reach Proxmox from WSL through an SSH ProxyCommand on the Windows host

- Status: Accepted
- Date: 2026-10-06
- Deciders: operator
- Decision log: D44 in docs/platform/requirements.md

## Context

Ansible and OpenTofu run in WSL (ADR 0010) and must reach the Proxmox VM at `10.99.0.2`, which sits behind a Hyper-V internal switch and NAT with port ACLs that admit the host's address only on ports 22 and 8006 (`scripts/hyperv/README.md:105`). WSL runs in NAT mode, in its own private subnet behind a different vEthernet.

Measured 2026-10-06 (after the VM was installed):
- Direct TCP to the VM on port 22 from WSL timed out, and a direct `ssh` failed with "Connection timed out".
- The same `ssh` through `ProxyCommand` with the Windows `ssh.exe -W %h:%p` printed the Proxmox version and exited 0.
- The root cause of the direct failure is not determined. Candidates: the inbound ACL admits only the host's own source address, or no route exists from the WSL subnet. Both need Hyper-V rights to separate and were not tested.

The earlier access decision adds no new listener on Windows and keeps the VM off every private network the host is attached to.

## Options considered

1. WSL mirrored networking — would put WSL on the host's own interfaces, which could make the ACL admit it. It changes networking for every WSL distro on the machine, including the one Docker Desktop uses. HYPOTHESIS: not tested here.
2. IP forwarding between the WSL and lab vEthernets — turns the Windows host into a router between two subnets and needs a route plus an ACL change. It widens the isolation surface the lab depends on and the port ACLs would still have to be loosened.
3. SSH `ProxyCommand` through the Windows `ssh.exe` — measured working; no host network change, no listener, no ACL change.

## Decision

Use option 3. The Ansible inventory (`iac/ansible/inventory/pve01.yml`, PR #59) sets the SSH arguments so each connection is proxied through the Windows `ssh.exe -W %h:%p`. OpenTofu's HTTPS to port 8006 goes through an SSH local forward over the same path.

- Two ed25519 keys are used. The proxy hop uses the Windows-side key because Windows OpenSSH refuses key files that carry WSL-style permissions. The inner session uses the WSL-side automation key. The Windows key path is supplied by an environment variable, never written to the repository.

## Rationale and trade-offs

- It is the only option with a measured pass and no change to the host network or the ACL set; the other two change exactly what the isolation design protects.
- The control path now depends on the Windows side being present and its `ssh.exe` working. On a VPS or any host with a direct route, the proxy is dropped by editing inventory data; no role code changes.
- Each connection spawns a Windows process; Ansible pipelining and a keepalive interval in the inventory limit the cost. Overhead and throughput were not measured.
- Revisit if the direct-path failure is shown to be a missing route (a one-line fix) or if WSL networking changes for another reason.
