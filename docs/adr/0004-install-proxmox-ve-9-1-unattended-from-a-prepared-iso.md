# 0004. Install Proxmox VE 9.1 unattended from a prepared ISO

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D8, D23, D34, D35 in docs/platform/requirements.md

## Context

The install must be repeatable from code (R2) and the VM must carry a restore point before any risky step (R13). Facts that constrain it:

- The Proxmox VE 9.2 installer is reported not to boot on Hyper-V Generation 2, while 9.1-1 does (forum.proxmox.com thread 183899). Proxmox Bugzilla 8027, "Cannot be installed in nested Hyper-V", was status NEW with no fix on 2026-10-06 (https://bugzilla.proxmox.com/show_bug.cgi?id=8027).
- An automated installer that finds an empty disk installs, reboots, and would install again if the DVD still wins the boot order, wiping the disk.
- Whether a Hyper-V checkpoint works for a VM with nested virtualization exposed was unproven.
- The VM has 20 GiB of RAM for guests (ADR 0003).

## Options considered

1. ISO 9.2-1 — newest; reported not to boot on Hyper-V Generation 2.
2. ISO 9.1-1, then `apt full-upgrade` to the latest 9.x — boots; the upgrade is a separate, codified step (ADR 0005).
3. Interactive install by hand — no answer file to maintain; not reproducible and not reviewable.

For the root filesystem: ext4 on LVM-thin (installer default), or ZFS. For the restore point: a checkpoint taken while the VM is Off, a running-VM checkpoint, or a copy of the VHDX.

## Decision

Verify the stock 9.1-1 ISO against the publisher's `SHA256SUMS` (and its signature), prepare it with `proxmox-auto-install-assistant` inside WSL (`scripts/proxmox/build-auto-install-iso.sh:128`), and install unattended from the answer file `iac/proxmox/answer.pve01.toml.tmpl`: ext4 on LVM-thin (`:20`) and `reboot-mode = "power-off"` (`:9`). The VM boot order is disk first, DVD second (`New-PveHost.ps1:391`), so an empty disk falls through to the installer and an installed disk boots from itself. The first restore point is a checkpoint named `post-install`, taken while the VM is Off with the ISO ejected (`New-PveHost.ps1:580`). The prepared ISO holds the root-password hash and is deleted after the install.

## Rationale and trade-offs

- Measured 2026-10-06 (#58): the unattended 9.1-1 install finished in 459 s and the VM powered itself off, so `reboot-mode = "power-off"` works on 9.1-1; the checkpoint was taken while Off; the first cold start answered on TCP 22 after 18.1 s.
- The power-off plus boot order removes the double-install risk: after the install the disk boots and the DVD is never reached.
- Checkpoint on a running nested VM stays unmeasured; only the stopped case is proven, and it is the one used. A VHDX copy is the fallback while the disk is small.
- ext4 on LVM-thin keeps snapshots and linked clones without ZFS. The Proxmox documentation (https://pve.proxmox.com/wiki/ZFS_on_Linux, memory section; figure paraphrased from the operator's notes) gives a default ZFS cache of 10 % of host memory, capped at 16 GiB; on a 20 GiB VM that is memory the guests need.
- Accepted cost: 9.1-1 is not the newest ISO, so the first boot runs older packages until the upgrade. The 9.1-1 installer accepts the answer file written for it (answer keys up to 8.4-1, `validate-answer` exit 0, install completed).
- HYPOTHESIS to re-check: if Bugzilla 8027 is fixed, a newer ISO can replace 9.1-1; check the bug before each ISO download.
