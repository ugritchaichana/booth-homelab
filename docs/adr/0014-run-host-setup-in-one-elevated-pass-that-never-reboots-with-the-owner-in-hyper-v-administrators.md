# 0014. Run host setup in one elevated pass that never reboots, with the owner in Hyper-V Administrators

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D26, D28, D30, D36, D43 in docs/platform/requirements.md

## Context

Creating the VM, its switch, NAT and port ACLs needs Hyper-V rights. The operator's shell is not elevated; the account is a local administrator and elevation works only after the owner accepts a UAC prompt (measured 2026-10-06: a no-op `RunAs` returned `elevated=True` in 3 s after acceptance). The Hyper-V Administrators group had 0 members. Enabling Hyper-V needs a Windows reboot, which ends the operator's session, and the workstation is used daily for other work.

The scripts that run elevated are in `scripts/hyperv/` and land through a pull request (#58).

## Options considered

1. Elevate per step, UAC on every VM start and stop, scripts reboot when needed — no standing rights, but a prompt per step and per start, and a surprise reboot on a working machine.
2. One elevated pass, owner added to Hyper-V Administrators, no reboots, owner reads the scripts before the run — same rights as option 3, plus a human read of every line.
3. The same one-pass design, with no owner review; independent security reviews and a PR carrying real output replace the review.

## Decision

Option 3.

- `New-PveHost.ps1` is one elevated run that carries every step needing Hyper-V rights: host setup, VM creation, unattended install, waiting for power-off, checkpoint while stopped, ISO eject, start, wait for SSH, with a transcript (D36). It never self-elevates and never reboots; when a restart is needed it stops and says so (`scripts/hyperv/New-PveHost.ps1:738`, `scripts/hyperv/README.md:7`) (D28).
- The owner is added to Hyper-V Administrators so later start, stop and checkpoint run non-elevated (`scripts/hyperv/pve01.psd1:6`); it takes effect at the next sign-in (D26). Setting `AddOwnerToHyperVAdministrators` to `$false` declines it without a code change (`scripts/hyperv/README.md`, Switching off the group membership).
- Disclosed to and re-confirmed by the owner (D43): membership is not filtered by UAC. Any process running as the owner can change or remove the VM's port ACLs, read the VM disk, and is widely reported to be able to reach host-administrator rights (HYPOTHESIS, not tested). Only the Windows Firewall rule stays outside that reach (`scripts/hyperv/README.md`, Isolation layer, Windows Defender Firewall). Group scope: https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-groups#hyper-v-administrators. The workstation is used by the owner alone; every local administrator is inside the trust boundary.
- No owner review of the scripts (D30). Compensating controls: independent security reviews before the run, and the PR carries the real run output.

## Rationale and trade-offs

- Reviews, by role: a security review of the host scripts, a security review of secrets and supply chain, a go/no-go review of the final bytes, and a delta review of the last change. None reported a finding that blocked the install; the host-script review named one finding that blocks registering any runner (at review time the host-routed deny prefixes were read only at VM start (a persisted union has since landed)). The bytes that ran were compared by hash with the bytes reviewed before the run.
- Failure-closed behaviour, measured 2026-10-06: the first run stopped at `Connect-VMNetworkAdapter` with error 0x80070057 because the switch rejected one ACL shape. The VM had been created with no switch attached, so it never started and was never connected. A probe on a throwaway VM found the cause; the fixed second run exited 0 (install 459 s, first cold start 18.1 s to SSH) (#58).
- Accepted cost: the owner's account can weaken the network isolation without UAC. Revisit if the machine gains a second regular user. Before any runner is registered, the scheduled isolation refresh that the host-script review required must exist.
