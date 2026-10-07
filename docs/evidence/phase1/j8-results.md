# J8 post-install verification, pve01 (PVE 9.1.1, kernel 6.17.2-1-pve)

Date 2026-10-06. Run non-elevated; no Hyper-V cmdlets, no firewall changes, no PVE config/package changes. Raw output (real addresses, local only): `j8-raw.txt`.

Labels: `<pve01>` guest, `<host-gw>` host side of the private switch, `<home-router>`, `<host-wifi>`, `<tailnet-peer-self>` (tailnet interface), `<mesh-self>` (mesh-VPN interface), `<mesh-dns>` (the mesh-VPN DNS server), `<guest-bcast>` guest-subnet broadcast.

PVE negatives use `timeout 4 bash -c '</dev/tcp/H/P'`. rc=124 means the SYN was silently dropped (ACL/firewall behaviour). rc=1 "Connection refused" would mean the target answered RST, i.e. not blocked. Method control: from PVE, 1.1.1.1:443 gives rc=0, and `<pve01>`:1 gives rc=1 "Connection refused", so the probe distinguishes open, refused and dropped.

## Test 2: Windows to guest, default deny inbound

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 2a positive | `Test-NetConnection <pve01> -Port 22` | True | True | PASS |
| 2b positive | `Test-NetConnection <pve01> -Port 8006` | True | True | PASS |
| 2c ICMP | `Test-Connection <pve01> -Count 2 -Quiet`; control `Test-Connection 1.1.1.1 -Quiet` | False; control True | False; control True | PASS |
| 2d non-allowed port, real listener | PVE `python3` listener on 0.0.0.0:9999 (`ss -ltnp` shows it; PVE self-connect rc=0); Windows `Test-NetConnection <pve01> -Port 9999` | False | False | PASS |
| 2e non-allowed port, existing listener | PVE `spiceproxy` already LISTENs on 3128 (the plan's `nc -l 3128` port); Windows to `<pve01>`:3128 | False | False | PASS |

## Test 3: guest egress and denies (PVE shell). Windows column = positive control for the same host:port

| Test | Command (PVE) | Expected | Actual (PVE) | Windows control | Verdict |
|---|---|---|---|---|---|
| 3a HTTPS | `curl -sS -m8 -o /dev/null -w '%{http_code}' https://deb.debian.org/` | code | 200, rc=0 | n/a | PASS |
| 3b HTTPS | same, `https://example.com` | code | 200, rc=0 (again 200 after all negatives) | n/a | PASS |
| 3c DNS | `cat /etc/resolv.conf`; `getent hosts deb.debian.org` | resolves via 1.1.1.1 | only `nameserver 1.1.1.1`; resolved (returned an AAAA first), rc=0 | n/a | PASS |
| 3d guest to host 445 | `</dev/tcp/<host-gw>/445` | blocked | rc=124 | True | PASS |
| 3e guest to host 135 | `</dev/tcp/<host-gw>/135` | blocked | rc=124 | True | PASS |
| 3f guest to host 139 | `</dev/tcp/<host-gw>/139` | blocked | rc=124 | True | PASS |
| 3g guest to host 53 | `</dev/tcp/<host-gw>/53` | blocked | rc=124 | False (host has no listener) | NOT PAIRED, no conclusion |
| 3h home router 80 | `</dev/tcp/<home-router>/80` | blocked | rc=124 | True | PASS |
| 3i home router 53 | `</dev/tcp/<home-router>/53` | blocked | rc=124 | True | PASS |
| 3j host Wi-Fi address 445 | `</dev/tcp/<host-wifi>/445` | blocked | rc=124 | True | PASS |
| 3k host Wi-Fi address 139 | `</dev/tcp/<host-wifi>/139` | blocked | rc=124 | True | PASS |
| 3l tailnet self 445 | `</dev/tcp/<tailnet-peer-self>/445` | blocked | rc=124 | True | PASS |
| 3m mesh-VPN self 445 | `</dev/tcp/<mesh-self>/445` | blocked | rc=124 | True | PASS |
| 3n mesh-VPN DNS 53 | `</dev/tcp/<mesh-dns>/53` | blocked | rc=124 | True | PASS |
| 3o ping, Internet | `ping -c2 -W2 1.1.1.1` | FAIL (stateful rules are TCP/UDP only) | 2 sent, 0 received, rc=1 | Windows `Test-Connection 1.1.1.1` True | PASS as predicted; see finding 1 |
| 3p ping, host | `ping -c2 -W2 <host-gw>` | no reply | 0 received, rc=1 | n/a | PASS |
| 3q broadcast | `ping -b -c2 -W2 <guest-bcast>` | no reply | 0 received, rc=1 | n/a | PASS |
| 3r multicast | `ping -c2 -W2 224.0.0.1` | no reply | 0 received, rc=1 | n/a | PASS |
| 3s IPv6 global | `ping -6 -c2 -W2 2606:4700:4700::1111`; `curl -6 https://example.com` | no reply | "Network is unreachable" (no IPv6 default route); curl code 000 | n/a | PASS |
| 3t IPv6 multicast | `ping -6 -c2 ff02::1%vmbr0` | no reply | 2 replies, but only from PVE's own link-local address, 0.03 ms (loopback echo, no foreign host) | n/a | PASS (not a leak) |
| 3u UDP DNS to host | plan's `dig @<host-gw>` | times out | SKIPPED: no `dig`/`nc` in PVE, and `/dev/udp` cannot show a drop | n/a | NOT MEASURED |
| 3v home public IP via forwarded port | plan's `home-wan-reflection` | blocked | SKIPPED: no public IP / forwarded port supplied | n/a | NOT MEASURED |

Not run (needs Hyper-V rights or firewall changes): Test 1 read-back, Test 5 plane isolation, and every Test 0 / Test 4 step that starts the VM.

## Test 4: host-routed VPN prefixes (steps 3 and 4), current state only

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 4 positive | Windows TCP to hosts inside the two harvested prefixes (`<vpn-prefix-host>`): two ARP neighbours (both Stale) probed on 80, 443, 22, 53, 3306, 5432, 6379, 8080, plus ICMP | one succeeds | all 16 TCP probes False, both pings False | NOT MEASURED |
| 4 negative | PVE to the same | blocked | not run, because the positive does not exist | NOT MEASURED |

Why: the VPN client lists the peers that own those prefixes as `Connecting`, with no handshake; the only `Connected` peers carry other prefixes (none of them harvested), and probes to three of those peers were also all False. No address inside a harvested prefix is reachable from Windows now, so a PVE timeout would prove nothing. Methods tried: open TCP connections, DNS cache, ARP neighbours, the VPN client's peer and route listing. Re-run when a peer for a harvested prefix is Connected.

Route-table coverage (measured, current state): the VPN interface routes six /16 prefixes right now; 4 fall inside the RFC1918 static deny, 2 are the harvested pair, 0 are uncovered. This does not replace the reachability test.

Route-table coverage (measured, current state): the VPN interface routes six /16 prefixes right now; 4 fall inside the RFC1918 static deny, 2 are the harvested pair, 0 are uncovered. This does not replace the reachability test.

Supplementary, NOT a Test 4 substitute: the mesh DNS server (`<mesh-dns>`:53, inside the 100.64/10 deny, not in a harvested prefix). Windows True, PVE rc=124 (row 3n). This shows the guest cannot reach a VPN-side address Windows reaches, but it exercises the static CGNAT deny, not the harvested-prefix path (`route-harvest-is-transient` stays unmeasured).

## WSL to guest (decides whether Phase 2 Ansible can run from WSL)

| Test | Command (WSL distro Debian, root) | Expected | Actual | Verdict |
|---|---|---|---|---|
| W1 direct TCP | `timeout 5 bash -c '</dev/tcp/<pve01>/22'` | HYPOTHESIS: fails | rc=124 (WSL is NAT mode: eth0 in its own private /20, default via the host-side WSL vEthernet) | CONFIRMED fail |
| W2 direct SSH | `ssh -o BatchMode=yes -i /root/.ssh/homelab_pve01_ed25519 root@<pve01> pveversion` | fails | "Connection timed out", rc=255 | CONFIRMED fail |
| W3 fallback | same `ssh` with `-o ProxyCommand="/mnt/c/Windows/System32/OpenSSH/ssh.exe -i <user-home>/.ssh/homelab_pve01_ed25519 -W %h:%p root@<pve01>"` | works | `pve-manager/9.1.1/42db4a6cf33dac83 (running kernel: 6.17.2-1-pve)`, rc=0 | PASS |

Phase 2 Ansible from WSL: direct connections do not work; the ProxyCommand route through the Windows ssh.exe does, so Ansible needs `ansible_ssh_common_args` with that ProxyCommand (or `ansible_ssh_extra_args`). Root cause of W1/W2 not determined (candidates: the inbound ACL admits only the host's own source address on 22/8006, or no route from the WSL subnet; both unmeasurable without Hyper-V rights). Side effect: W3 added the guest host key to WSL root's `known_hosts` (`StrictHostKeyChecking=accept-new`).

## ISO cleanup

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 5 | `Remove-Item -LiteralPath <local-app-data>\homelab\iso\pve01-auto.iso`, then `Test-Path` | False | removed without error; `Test-Path` = False; official `proxmox-ve_9.1-1.iso` (1831886848 bytes) and `SHA256SUMS` still present | PASS |

Rollback is regeneration from the official ISO (no backup, by design: the file held the root-password hash). One line added to `<operator-dir>/logs/change-log.md`.

## Findings that did not behave as designed or need a decision

1. ICMP to the Internet fails from the guest (3o), as predicted. The guest therefore has no ping and no ICMP-based path-MTU discovery signal; HTTPS worked at normal MTU in this run, so a PMTU black hole is a risk for larger transfers but not observed (HYPOTHESIS, not measured). Reported, not changed.
2. 3g is not a valid negative: the host has no DNS listener on 53, so the block was not demonstrated for that port. The plan's UDP DNS-to-host negative could not be run with the tools in PVE.
3. PVE reports an IPv6 link-local address on `vmbr0` and answers IPv6 multicast from itself; there is no IPv6 default route, and global IPv6 fails with "Network is unreachable".
4. Planes are not isolated here: the host firewall block and the port ACLs both cover guest-to-host traffic and nothing was toggled (no elevation). Every guest-to-host negative proves "blocked by at least one layer", not which one; for the Wi-Fi, router and VPN addresses the same applies to ACL versus host routing.
5. Test 4 (harvested prefixes) is NOT MEASURED, see above.
6. The host's sshd is Stopped, so port 22 on host-side addresses was not usable as a negative target; 445/139/135 were used instead.
