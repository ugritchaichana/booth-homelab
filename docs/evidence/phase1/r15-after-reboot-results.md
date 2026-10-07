# R15 isolation evidence after reboot, pve01 (PVE 9.2.21, kernel 7.0.14-20-pve)

Date 2026-10-06, 18:50-19:03 ICT. Host rebooted 18:42; VM started 18:49 through `Invoke-PveVm.ps1 -Action Start`. Run non-elevated (Hyper-V Administrators token); no Windows Firewall change, no checkpoint create/restore/delete, no repo file edited. Raw output with real addresses (local only): `r15-after-reboot-raw.txt`.

Labels: `<host-lan>` host Wi-Fi address, `<home-router>` home router, `<host-tailnet>` host tailnet address, `<host-vpn>` host address on the VPN interface `wt0`, `<vpn-dns>` the DNS server the VPN client pushes, `<vpn-prefix-1>` / `<vpn-prefix-2>` the two host-routed prefixes harvested by Start (both /16), `<vpn-peer-N>` an address inside a harvested prefix, `<VM id>` the VM GUID. Reserved ranges are named by class, not by number.

PVE negatives use `timeout 4 bash -c '</dev/tcp/H/P'` as in j8: rc=124 is a silently dropped SYN, rc=1 "Connection refused" would mean the target answered. Method control this run: PVE to 1.1.1.1:443 rc=0 and to 10.99.0.2:1 rc=1 "Connection refused". Windows controls use a 3 s `TcpClient` connect.

## Test 1: read-back shape (Windows)

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 1a rule count | `Get-VMNetworkAdapterExtendedAcl -VMName pve01` | 18 | 18 | PASS |
| 1b out of range | same, `Weight -lt 4000 -or -gt 4999` | 0 | 0 | PASS |
| 1c shape | same, sorted by Weight | 2 inbound stateful allow (22, 8006 from 10.99.0.1), `::/0` both directions, 9 static outbound denies, 2 harvested denies, 2 outbound stateful allows, 1 inbound default deny | exactly that: weights 4999, 4998, 4989, 4988, 4899-4891 (the 9 static reserved-range denies of the plan), 4890 and 4889 (`<vpn-prefix-1>`, `<vpn-prefix-2>`), 4010 TCP, 4009 UDP, 4000 inbound deny for all IPv4 | PASS |
| 1d `::/0` and `ANY` accepted, any-protocol display, stateful count | read-back | accepted; any-protocol shows `ANY`; one entry per stateful rule | `::/0` read back, Protocol `ANY`, the 4 stateful rules are 4 entries (not 8) | PASS (settles the read-back item) |
| 1e adapter | `Get-VMNetworkAdapter -VMName pve01` | spoofing Off, DhcpGuard On, RouterGuard On | `Off` / `On` / `On`, DynamicMacAddressEnabled False, switch `homelab-pve01` | PASS |
| 1f host rule | `Get-NetFirewallRule -Name homelab-pve01-block-guest-inbound` | Enabled True, Block | `True`, `Block`, Inbound, Profile Any | PASS |
| 1g IPv6 binding | `Get-NetAdapterBinding -Name 'vEthernet (homelab-pve01)' -ComponentID ms_tcpip6` | False | reads `Enabled False` (the earlier read failure is gone) | PASS |

## Test 2: Windows to guest, default deny inbound

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 2a positive | `Test-NetConnection 10.99.0.2 -Port 22` | True | True | PASS |
| 2b positive | `Test-NetConnection 10.99.0.2 -Port 8006` | True | True | PASS |
| 2c ICMP | `Test-Connection 10.99.0.2 -Count 2 -Quiet`; control `Test-Connection 1.1.1.1 -Quiet` | False; control True | False; control True | PASS |
| 2d non-allowed port, real listener | PVE `systemd-run --unit=r15-listen python3 -m http.server 9999` (`ss -ltnp` shows the all-interfaces address on port 9999, PVE self-connect rc=0); Windows connect to 10.99.0.2:9999 (`TcpClient` and `Test-NetConnection`) | False | False, False; unit stopped afterwards (`inactive`, 0 listeners on 9999) | PASS |
| 2e non-allowed port, existing listener | `spiceproxy` LISTENs on `*:3128` (`ss -ltnp`); Windows to 10.99.0.2:3128 | False | False | PASS |

## Test 3: guest egress and denies (PVE shell). Windows column = positive control for the same host:port

| Test | Command (PVE) | Expected | Actual (PVE) | Windows control | Verdict |
|---|---|---|---|---|---|
| 3a HTTPS | `curl -sS -m8 -o /dev/null -w '%{http_code}' https://deb.debian.org/` | code | 200, rc=0 | n/a | PASS |
| 3b HTTPS | same, `https://example.com` | code | 200, rc=0 (3a returned 200 again after 5b and after 6) | n/a | PASS |
| 3c DNS | `grep -v '^#' /etc/resolv.conf`; `getent hosts deb.debian.org`; `dig @1.1.1.1 example.com +short +time=2` | resolves via 1.1.1.1 | `nameserver 1.1.1.1` only; getent rc=0 (AAAA first); dig answered with 1 A record | n/a | PASS |
| 3d guest to host 445 | `</dev/tcp/10.99.0.1/445` | blocked | rc=124 | True | PASS |
| 3e guest to host 135 | `</dev/tcp/10.99.0.1/135` | blocked | rc=124 | True | PASS |
| 3f guest to host 139 | `</dev/tcp/10.99.0.1/139` | blocked | rc=124 | True | PASS |
| 3g guest to host 53 (TCP) | `</dev/tcp/10.99.0.1/53` | blocked | rc=124 | False (no TCP listener) | NOT MEASURED (unpaired, no conclusion) |
| 3h home router 80 | `</dev/tcp/<home-router>/80` | blocked | rc=124 | True | PASS |
| 3i home router 53 | `</dev/tcp/<home-router>/53` | blocked | rc=124 | True | PASS |
| 3j host LAN address 445 | `</dev/tcp/<host-lan>/445` | blocked | rc=124 | True | PASS |
| 3k host LAN address 139 | `</dev/tcp/<host-lan>/139` | blocked | rc=124 | True | PASS |
| 3l tailnet self 445 | `</dev/tcp/<host-tailnet>/445` | blocked | rc=124 | True | PASS |
| 3m VPN-interface self 445 | `</dev/tcp/<host-vpn>/445` | blocked | rc=124 | True | PASS |
| 3n VPN DNS 53 | `</dev/tcp/<vpn-dns>/53` | blocked | rc=124 | True | PASS |
| 3o ping, Internet | `ping -c2 -W2 1.1.1.1` | FAIL (stateful rules are TCP/UDP only) | 2 sent, 0 received | Windows `Test-Connection 1.1.1.1` True | PASS as predicted; see finding 1 |
| 3p ping, host | `ping -c2 -W2 10.99.0.1` | no reply | 0 received | n/a | PASS |
| 3q broadcast | `ping -b -c2 -W2 10.99.0.255` | no reply | 0 received | n/a | PASS |
| 3r multicast | `ping -c2 -W2 224.0.0.1` | no reply | 0 received | n/a | PASS |
| 3s IPv6 global | `ping -6 -c2 -W2 2606:4700:4700::1111`; `curl -6 https://example.com` | no reply | "Network is unreachable"; curl code 000 (connect failed) | n/a | PASS |
| 3t IPv6 multicast | `ping -6 -c2 -W2 ff02::1%vmbr0` | no reply | 2 replies at 0.03-0.06 ms, loopback echo from the guest's own link-local address | n/a | PASS (not a leak, as in j8) |
| 3u UDP DNS to host | `dig @10.99.0.1 example.com +time=2 +tries=1` (`dig` now exists in PVE) | times out | "communications error ... timed out" | host has a UDP 53 endpoint (system service) but Windows `nslookup example.com 10.99.0.1` also got "No response from server" | NOT MEASURED (unpaired, no conclusion) |
| 3v home public IP via forwarded port | plan's `home-wan-reflection` | blocked | not run: no public IP or forwarded port supplied | n/a | NOT MEASURED |

`nc -zvu` against 10.99.0.1:53 printed "open" with rc=0; UDP gives no handshake, so that output is not evidence and was not used.

## Test 4: host-routed VPN prefixes, basic (harvested-prefix negative)

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 4 positive | Windows TCP to `<vpn-peer-N>` inside the two harvested prefixes: the two routing-peer addresses on 80, 443, 22, 53, 3306, 5432, 6379, 8080 (16 connects) plus 5 peer-named addresses on 22, 443, 80 (15 connects), plus ICMP to the two routing peers | at least one succeeds | all 31 TCP connects False, both pings False | NOT MEASURED |
| 4 negative | PVE to the same | blocked | not run, because the positive does not exist | NOT MEASURED |

Why: the VPN client now lists the routing peer for each harvested prefix as `Connected` (relayed, WireGuard handshake under 3 minutes old), and Windows routes both prefixes through `wt0` (`Find-NetRoute` shows the `<vpn-prefix-2>` route on `wt0`). Still nothing inside those prefixes answered on the short port list, and the ARP entries for the two routing-peer addresses ended `Unreachable` / `Probe`. A PVE timeout would prove nothing without a Windows positive. Methods tried: open TCP connections, ICMP, ARP neighbours on `wt0`, DNS cache (no entry in either prefix), the VPN client's peer and route listing. Not run, per instruction: the "VPN disconnected at Start" ordering variant and the full-tunnel step.

Supporting measurement (not a Test 4 substitute): VPN-interface routes are 7 /16 prefixes (6 remote, 1 the interface's own). Checked against the Outbound Deny prefixes read back in Test 1: 2 are exact matches of the harvested denies (4890, 4889), 3 fall in the RFC1918 class-B deny, 1 in the RFC1918 class-A deny, 1 in the CGNAT deny, 0 uncovered. Start's `Status` output also reports the two harvested prefixes already in the local override ("would append 0 new"), so the override already held both prefixes before this Start. This is route-table coverage, not reachability.

## Test 5: plane isolation (rows needing no Windows Firewall change)

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 5a stateful mirror, negative | PVE `systemctl stop pveproxy` (no listener on 8006); `nc -zv -w3 -p 8006 10.99.0.1 445` | fails | "Connection timed out", rc=1 | PASS |
| 5a control, same without `-p 8006` | `nc -zv -w3 10.99.0.1 445` | fails | "Connection timed out", rc=1 | PASS (shows the source port made no difference) |
| 5a positive | `nc -zv -w3 -p 8006 1.1.1.1 443` | succeeds | "open", rc=0 | PASS |
| 5a restore | `systemctl start pveproxy` (EXIT trap and explicit) | active | `active` (8006 listener present again; Windows reaches 8006 in the later 5b restore check) | PASS |
| 5b ACLs removed, no-ACL window | `Disconnect-VMNetworkAdapter`; `Get-VMNetworkAdapterExtendedAcl \| Remove-VMNetworkAdapterExtendedAcl` (count 0); `Connect-VMNetworkAdapter -SwitchName homelab-pve01`; from PVE `ping -c1 1.1.1.1` and `nc -zv -w3 10.99.0.1 445` | ACLs gone; 445 fails | ACL count 0 confirmed; ping to 1.1.1.1 replied (1 received, which fails with ACLs present, so the ACL plane was really absent); `nc` 445 "Connection timed out", rc=1 | PASS |
| 5b window log | `NOACL-WINDOW START` / `END` | short | START 19:00:39.756; PVE probes 19:00:45-19:00:48 (first ssh attempt failed while the link came up); `Refresh` began 19:00:47.697; END 19:00:54.577 with ACL count 18; about 14.8 s total | recorded |
| 5b restore, Test 1 repeat | `Invoke-PveVm.ps1 -Action Refresh`, then Test 1 | 18 | Refresh: "added 18, removed 0"; read-back 18, 0 out of range, same shape as Test 1c, spoofing Off, guards On; 22 and 8006 reachable; PVE `ping 1.1.1.1` again 0 received, curl 200 | PASS |
| 5c rows "Port ACLs alone", "Host default inbound block" | need `Disable-NetFirewallRule` (elevation) | not run | script written, not executed: `r15-test5-elevated.ps1` | NOT MEASURED (by design) |

## Test 6: L2 (MAC spoofing), no console

Launched on PVE with `systemd-run --unit=r15-l2 --collect /bin/bash /root/r15-l2.sh` at 19:01:44; the script logs to `/root/r15-l2.log`. SSH reconnected on the first attempt at 19:02:26; no `Restart-VM` was needed.

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 6a spoof | `ip link set dev vmbr0 address 00:15:5d:99:00:99`, wait 3 s, `curl -m5 https://deb.debian.org/` | fails | `set spoof rc=0`, mac_now 00:15:5d:99:00:99; curl "(28) Resolving timed out after 5000 milliseconds", code 000 | PASS |
| 6b restore | restore to 00:15:5d:99:00:02, wait 3 s, curl up to 3 tries | succeeds | `restore rc=0`, mac_now 00:15:5d:99:00:02; try 1 code 200, rc=0 (19:01:56) | PASS |
| 6c cleanup | `/root/r15-l2.sh`, `/root/r15-l2.log` deleted; unit gone | gone | `ls ~ \| grep -c r15` = 0; `r15-l2` and `r15-listen` `inactive` | PASS |

The EXIT trap fired a second restore at 19:01:56 (idempotent, same MAC). The spoofed-state failure is DNS resolution (the first thing the curl does), not only HTTPS.

## Test 7: rights and file ACLs (Windows)

| Test | Command | Expected | Actual | Verdict |
|---|---|---|---|---|
| 7a group in token | `whoami /groups \| findstr S-1-5-32-578` | present | `BUILTIN\Hyper-V Administrators ... Mandatory group, Enabled by default, Enabled group` in a non-elevated token | PASS |
| 7b folder | `icacls C:\HyperV\pve01` | four ACEs, no inheritance | SYSTEM (F), Administrators (F), Hyper-V Administrators (M), `NT VIRTUAL MACHINE\Virtual Machines` (M), all `(OI)(CI)`, none `(I)` | PASS |
| 7c VHDX | `icacls C:\HyperV\pve01\pve01.vhdx` | per-VM ACE | `NT VIRTUAL MACHINE\<VM id>:(R,W)` present, plus one unresolved capability SID `(R,W)` and four inherited `(I)` ACEs from the folder | PASS (settles the per-VM ACE item) |

## End state (checked after the last test)

| Check | Result |
|---|---|
| VM | Running (uptime 14 min; checkpoints `post-install`, `pre-ansible-2` unchanged) |
| `Invoke-PveVm.ps1 -Action Status` | 22 reachable True, 8006 reachable True, 18 port ACL rules (a fresh refresh would hold 18), host rule present, IPv6 binding False |
| Host rule | `Enabled True`, `Action Block` |
| PVE | `ip -br link show vmbr0` = 00:15:5d:99:00:02; `pveproxy` active |

## Findings that did not behave as designed or need a decision

1. ICMP from the guest to the Internet still fails (3o), and the first guest probe with ACLs removed (5b) replied, so this is caused by the ACLs: the stateful allows are TCP/UDP only. The guest has no ping and no ICMP-based path-MTU discovery; HTTPS worked at normal MTU, so a PMTU black hole for larger transfers is a HYPOTHESIS, not measured. Unchanged since j8; reported, not changed.
2. Test 4 basic is still NOT MEASURED. New since j8: both routing peers for the harvested prefixes are `Connected` and the routes are on `wt0`, but no address in either prefix answers from Windows (31 connects, 2 pings), so the "PVE must fail" half has no valid positive. Re-run when a host inside a harvested prefix is known to answer (for example a named service in that network).
3. Planes are still not isolated (5a, 5b). In 5b the ACLs were really gone (ICMP to 1.1.1.1 replied) and PVE to host 445 still timed out, so the host side (Defender rule and the profile's default inbound block) stopped it alone; that does not separate the rule from the default block. 5a's control without `-p 8006` failed identically, so the mirror negative shows no behaviour specific to source port 8006. The two rows that discriminate need elevation: run `r15-test5-elevated.ps1`. That script disables the rule and tests the plain probe and the `-p 8006` mirror with the ACLs still in place (ACL plane alone); the "Host default inbound block" row additionally needs the ACLs removed, which the script deliberately does not do.
4. 5b left the guest with no egress ACLs for about 14.8 s (the refresh itself took about 7 s). Only benign probes ran in the window.
5. 3g and 3u are unpaired: the host has no TCP 53 listener, and the UDP 53 endpoint it does have did not answer a Windows `nslookup` either, so the PVE timeouts do not demonstrate a block for port 53. 3v needs a public IP and a forwarded port, not supplied.
6. `dig` and `nc` (traditional) are now present in PVE; j8 recorded neither. This made 3u and the `-p` source-port probes runnable. Not investigated why.
7. The VHDX carries four inherited `(I)` ACEs including Hyper-V Administrators (M) and an unresolved capability SID with (R,W), beyond the per-VM ACE the plan expects; consistent with inheritance from the folder, not a change.
8. Process note: the first 2d/2e lines in the raw file are invalid (a helper name collided with a PowerShell alias, so the listener was never started); the redo is labelled in the raw file and is what this report uses.
