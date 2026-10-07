# Proxmox VE on Hyper-V (Windows host)

Creates one nested-virtualization VM, `pve01`, on a Windows 11 Pro (or Server 2022+) host, behind an internal switch and NAT, with a host-side isolation layer. Windows PowerShell 5.1 compatible (also parses in PowerShell 7).

| File | Role |
|---|---|
| `New-PveHost.ps1` | Elevated, one-time setup: host rights (optional), folder + ACL, switch, NAT, VM, isolation, optional unattended install. `-PlanOnly`, `-Uninstall`, `-ShowPrefixes`. Never reboots, never self-elevates. |
| `Invoke-PveVm.ps1` | Day-to-day, non-elevated: `-Action Start`, `Stop`, `Status`, `Refresh`, `Checkpoint`. |
| `Test-R15Controls.ps1` | Windows-side paired controls for the R15 proof: reaches the same targets from the host while the guest is blocked (`tests/isolation/README.md`). |
| `HomelabHyperV.psm1` | Shared functions (config loading, CIDR math, port ACL plan and sync, firewall rule, rights checks). |
| `pve01.psd1` | All names, sizes, addresses, MAC, ports, thresholds. Another host gets its own `.psd1` via `-ConfigPath`. |
| `tests/hyperv/` | Pester 5.7.1 unit tests with every Hyper-V and network cmdlet mocked, so no Hyper-V role is needed: after `Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck`, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\hyperv\Invoke-HyperVTests.ps1` (prints the line coverage of `HomelabHyperV.psm1`). |

## Design in one table

| Item | Value |
|---|---|
| VM | Gen2, Secure Boot off, nested virtualization on, 12 vCPU, 20 GiB static memory, dynamic VHDX max 128 GiB |
| Network | Internal switch + NetNat `10.99.0.0/24`; host `10.99.0.1`, guest `10.99.0.2`; no port mapping, no new host listener; IPv6 binding disabled on the host vEthernet |
| MAC | Static, Hyper-V range (`00-15-5D-...`), spoofing off, DHCP guard and router guard on |
| Adapter | Created disconnected. It is connected only after the port ACLs read back clean and the firewall rule is verified |
| Checkpoints | Automatic checkpoints off; one `post-install` checkpoint taken while the VM is Off, after the ISO is detached |
| Start/stop | `AutomaticStartAction Nothing` (start on demand), `AutomaticStopAction ShutDown` |
| Boot order | Disk first, DVD second. An empty disk falls through to the DVD; after install the disk boots, so the installer cannot run twice |
| Files | `C:\HyperV\pve01\` (VM config, VHDX, ISO copy until the install finishes). Protected ACL: SYSTEM, Administrators, Hyper-V Administrators (`S-1-5-32-578`), VM worker group (`S-1-5-83-0`) |

## Run it

All lines are for `cmd.exe`, run from the repository root.

1. Preview, no elevation needed, changes nothing and writes no file:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -InstallIso "%LOCALAPPDATA%\homelab\iso\<prepared>.iso" -InstallIsoSha256 <64 hex> -Install -PlanOnly
```

2. Real run from an elevated Command Prompt (Run as administrator). One run carries everything that needs Hyper-V rights, through the install: host setup, VM create, start, wait until the VM powers itself off (timeout 45 min, progress every 30 s), eject the ISO (documented per-controller form, confirmed by read-back; the run stops before the checkpoint if media stays attached), checkpoint `post-install`, start, wait for TCP `10.99.0.2:22` (timeout 10 min), print the elapsed seconds of that first cold boot, then delete the ISO copy under `RootPath` (it holds the root-password hash). The transcript goes to `%LOCALAPPDATA%\homelab\logs\New-PveHost-<timestamp>.log`.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -InstallIso "%LOCALAPPDATA%\homelab\iso\<prepared>.iso" -InstallIsoSha256 <64 hex> -Install
```

`-InstallIsoSha256` is required whenever `-InstallIso` is given. The source ISO's SHA-256 is checked before any change is made, again before the copy, the copy under `RootPath` is checked after copying and once more before it is attached; any mismatch stops the run. Without `-Install` the VM is created but not started. `-Install` refuses if the VHDX is larger than `EmptyVhdxMaxMiB`, if the VM has checkpoints, or if the VM is not Off: it never reinstalls over data. The prepared ISO's answer file must power the VM off when the install ends (`reboot-mode = "power-off"`). The source ISO under `%LOCALAPPDATA%\homelab\iso\` is yours to delete; the script prints a reminder and never touches it.

3. By default the current user is added to Hyper-V Administrators (by SID, not by the localized name). That takes effect at the next sign-in; after that, no elevation is needed:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Refresh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Stop
```

- `Start` checks host RAM and the host firewall rule (refuses on either unless `-Force`), refuses if foreign extended ACLs exist on the adapter, refreshes the port ACLs from the current routes, reconnects the adapter if an earlier failure disconnected it, starts the VM and prints seconds until TCP 22 answers. On a running VM it only refreshes and reconnects.
- `Refresh` is for a running VM only: it syncs the port ACLs and exits 0 when the VM is Off. It never starts the VM and never reconnects a disconnected adapter. If the sync fails, the adapter is disconnected (fail closed) and the exit code is 1.
- `Stop` is graceful with a timeout; a hard power-off needs `-TurnOff -Force`.
- `Status` reports state, reachability, adapter connection, rule counts, foreign ACLs, egress interface and the firewall rule.

### Checkpoint

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Checkpoint -Name <name>
```

`<name>` is 1 to 63 lowercase letters, digits or hyphens, starting with a letter or digit. It exits 1 and takes no checkpoint when:
- the VM is not `Off` (stop it first with `-Action Stop`);
- a checkpoint with that name already exists;
- any DVD drive of the VM still has media attached;
- the free space on the VM's drive is already below `MinFreeDiskAfterGrowthGiB`.

Stopped-only because a standard checkpoint of a running VM stores its memory state on disk, and the VM type here is `Standard` (ADR 0019). After `Checkpoint-VM` the action polls for the checkpoint by id for up to 15 s (the list can lag the call), reads it back and requires its state to be `Off` with no media recorded; otherwise it removes that checkpoint and exits 1.

The worst case is printed as a `[WARN]` line, not a refusal: each checkpoint freezes the current disk and starts a new layer that can grow to the full disk size, so free space minus the disk size may be below the floor. `Remove-VMSnapshot` merges a layer back; remove a restore point once the step it protects is verified.

There is no restore action. Restore with Hyper-V Manager or `Restore-VMSnapshot`, then start the VM only with `-Action Start`: it re-syncs the port ACLs before `Start-VM`, which a start from Hyper-V Manager skips. A checkpoint taken before a credential rotation still holds the rotated-away secrets and restoring it makes them live again, so take a fresh checkpoint after every rotation and remove the older ones.

**Required before any runner registers: a scheduled task that runs `Refresh` on network change** (event log `Microsoft-Windows-NetworkProfile/Operational`, event 10000, per-user, no elevation). It is not created by these scripts; it needs its own review. Until it exists, a VPN or default-route change while the VM runs is picked up only by a manual `Refresh` or `Start`.

### Switching off the group membership

`AddOwnerToHyperVAdministrators` (default `$true` in `pve01.psd1`, overridable in the local file below) controls whether `New-PveHost.ps1` adds the current user to Hyper-V Administrators. With `$false`, nothing is added, and every `Invoke-PveVm.ps1` action then needs an elevated prompt.

### Exit codes

| Script | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `New-PveHost.ps1` | done | error or failed preflight | Hyper-V feature enabled with `-NoRestart`, reboot needed (the script never reboots) | - |
| `Invoke-PveVm.ps1` | ok | error | - | no Hyper-V rights in this session |

## Local override (never in the repo)

`%LOCALAPPDATA%\homelab\<config name>.local.psd1` (for `pve01.psd1`: `pve01.local.psd1`) is merged by the config loader. Only three keys are accepted: `StaticDenyPrefix`, `EgressInterfaceAlias`, `AddOwnerToHyperVAdministrators`. It is written by real runs (`New-PveHost.ps1`, `Start`, `Refresh`), never by `-PlanOnly`.

- `StaticDenyPrefix`: every host-routed prefix ever seen is appended and stays denied, even after the VPN disconnects. Nothing is dropped automatically; edit the file to remove one.
- `EgressInterfaceAlias`: the interface the guest may leave through. On first run it is recorded from the single interface that carries a default route. If default routes exist on several interfaces and none is configured, all guest egress is denied until you set it. After docking or switching networks (Wi-Fi to Ethernet), a default route on another interface also denies all egress (fail closed): edit the alias in this file, then run `Refresh`.
- `EgressInterfaceAlias` is a list. A docked laptop with Ethernet and Wi-Fi both carrying `0.0.0.0/0` stays deny-all unless both aliases are listed; routes on any listed interface are never added as denies.
- Run `New-PveHost.ps1` and `Invoke-PveVm.ps1` as the same Windows account (UAC elevation of that account, not a separate admin login): the override lives under that account's `%LOCALAPPDATA%`, and another account would read an empty `StaticDenyPrefix` and lose "seen once stays denied".
- The transcript header written by PowerShell (user name, machine, full command line including the ISO path) and engine error records are not masked. Redact before pasting a log anywhere public. Interface alias names (for example a VPN product name) are printed.
- Console output and the transcript never print host-routed prefixes: only a count and a SHA-256 of the sorted list. `-ShowPrefixes` prints them. Paths under the user profile are shown as `%LOCALAPPDATA%` / `%USERPROFILE%`.

## What the answer file must provide

`New-PveHost.ps1 -Install` only observes the VM: it waits for the power-off and then for TCP 22. It relies on the prepared ISO's answer file for:
- static `10.99.0.2/24`, gateway `10.99.0.1`;
- DNS set to a public resolver (not the gateway: `10.99.0.1` is inside the denied `10.0.0.0/8`);
- `reboot-mode = "power-off"`, so the first boot after install comes from the disk;
- sshd enabled on first boot.

## Rollback

From an elevated prompt, with confirmation (`-Confirm:$false` skips the prompt):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -Uninstall
```

Removes the VM (with its checkpoints), the NAT, the switch and the firewall rule. In the VM folder it deletes known files only (`*.vhdx`, `*.avhdx`, `*.iso`, the VM config files by VM id, the marker) and then empty folders; anything else is left and counted. The folder is touched only if it carries this script's marker. The Hyper-V Administrators membership is removed only if this script added it for the account running the command. Port ACLs go with the VM. The Windows Hyper-V feature is left enabled; the local override file is left in place. Add `-PlanOnly` to list what would be removed.

## Isolation layer (requirement: code in PVE must not reach host-attached networks)

Hyper-V extended port ACLs on the VM's network adapter, applied before the adapter is connected and refreshed on every `Start` and `Refresh`. Rules live in the weight range `AclWeightMin`-`AclWeightMax`; a refresh adds missing rules and removes stale ones only in that range. Any extended ACL outside the range makes `Start` and the setup run refuse. Larger weight applies first, and once a rule matches, lower ones are ignored.

| Rule | Direction | Action | Match | Why |
|---|---|---|---|---|
| Allow management | Inbound | Allow, stateful | from host `10.99.0.1`, TCP 22 and 8006 | management from the host; stateful so replies flow |
| Deny IPv6 | both | Deny | IPv6 `::/0` | no IPv6 (the host vEthernet also has its IPv6 binding disabled) |
| Deny private ranges | Outbound | Deny | `0.0.0.0/8`, `10/8`, `100.64/10`, `127/8`, `169.254/16`, `172.16/12`, `192.168/16`, `224/4`, `240/4` | private, CGNAT, link-local, multicast, reserved |
| Deny other routed prefixes | Outbound | Deny | every IPv4 prefix routed on an interface other than `EgressInterfaceAlias` and the homelab vEthernet, unioned with everything stored in the local override | catches VPN routes that are not private ranges, and keeps them after the VPN is gone |
| Allow internet TCP | Outbound | Allow, stateful, TCP | `0.0.0.0/0` (weight 4010) | internet out, replies flow |
| Allow internet UDP | Outbound | Allow, stateful, UDP | `0.0.0.0/0` (weight 4009) | internet out (DNS, NTP), replies flow |
| Deny internet, fail closed | Outbound | Deny | `0.0.0.0/0` (replaces the two allow-internet rules when a default route `0/0`, `0/1` or `128/1` sits on another interface) | fail closed: no egress through a tunnel |
| Default deny in | Inbound | Deny | `0.0.0.0/0` | default deny in |

Measured on this host (probe run, Windows 11 build 26200): the switch rejects, at the moment it applies the rules (`Connect-VMNetworkAdapter`), a stateful rule with no protocol, protocol `ANY`, or ICMP (`1`), a stateful Deny, and a weight of 100000 (65535 is accepted). **Stateful rules must therefore be TCP or UDP.** The plan refuses anything else before it is applied. Consequence: ICMP echo replies and inbound ICMP errors (including path-MTU 'fragmentation needed') hit the default deny, so `ping` to the internet from the guest fails and a lower-MTU path behind a VPN can stall TCP (fail closed; the inbound ICMP allow is listed under Not covered). `Add-VMNetworkAdapterExtendedAcl` accepts such a rule and the read-back lists it: only the connect step proves a rule shape.

Windows Defender Firewall: one inbound Block rule, all profiles, remote `10.99.0.0/24`, any local address, scoped to the homelab vEthernet. Block rules beat allow rules; replies to host-initiated sessions stay allowed because the filter is stateful. `Start` refuses unless the rule exists, is enabled, blocks and is inbound.

`-PlanOnly` prints the exact table without touching Hyper-V or writing any file; host-routed prefixes show as `(host-routed)`. A real run prints the table it applied and the table read back from Hyper-V.

Limits to know:
- The guest resolves DNS through a public resolver, not through `10.99.0.1` (denied by design).
- Hyper-V drops frames from MAC addresses other than the adapter's (spoofing off). Containers or VMs inside PVE must be routed or NATed by PVE, not bridged with their own MACs.
- Paths between guests inside PVE and PVE's own management are not visible to host-side rules.
- Prefixes reachable only through `EgressInterfaceAlias` are not blocked (for example a non-private network directly attached to it).
- Hyper-V sockets (guest to host over VMBus) are outside both planes; the Ansible role `hyperv_guest` blocks `hv_sock` inside PVE (ADR 0028).
- **Hyper-V Administrators membership is not filtered by UAC. Any process running as this user can change or remove the VM's network isolation, read the VM disk, and is widely reported to be able to reach host-administrator rights. Only the Windows Firewall rule stays outside that reach.** Set `AddOwnerToHyperVAdministrators` to `$false` to decline it.
- Setup writes through paths under `C:\HyperV`. It refuses reparse points (links) and folders not owned by Administrators or SYSTEM, but a user-created `C:\HyperV` must be deleted first.

## Sources

- Nested virtualization: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/nested-virtualization
- Extended ACL cmdlets (weights, stateful): https://learn.microsoft.com/en-us/powershell/module/hyper-v/add-vmnetworkadapterextendedacl
- Windows Firewall rule precedence: https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/rules
- Stateful filtering (WFP ALE): https://learn.microsoft.com/en-us/windows/win32/fwp/application-layer-enforcement--ale-
- Well-known SIDs (`S-1-5-32-578`, `S-1-5-83-0`): https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-identifiers
- Per-VM account on VM files: https://learn.microsoft.com/en-us/troubleshoot/windows-server/virtualization/hyper-v-virtual-machine-not-start-0x80070005

## Measured on this host

Results with their evidence files: `docs/handoff/results.md` (sections Isolation (R15) and Host, reboots and cold starts). The rows are in `docs/platform/requirements.md` section 3; transcripts are in `docs/evidence/phase1/` and `docs/evidence/phase2/`.

## Not covered

- A host inside a harvested VPN prefix: nothing there answers even from Windows, so the row cannot be told from an absent service (rows 38, 42).
- UDP from the guest to the host.
- The scheduled task that runs `Refresh` on a network change (see Run it). It must exist before any runner registers; it is a hand-off item in `docs/handoff/README.md`.
- Deferred: inbound ICMP allow for path-MTU discovery, home WAN address reflection through router port-forwards, and an ACL key that includes direction, protocol, port and stateful.
