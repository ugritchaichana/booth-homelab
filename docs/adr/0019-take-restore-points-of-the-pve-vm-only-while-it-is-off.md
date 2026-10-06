# 0019. Take restore points of the PVE VM only while it is Off

- Status: Accepted
- Date: 2026-10-06
- Deciders: operator
- Decision log: D23 in docs/platform/requirements.md

## Context

Risky steps on the PVE VM (package upgrades, configuration changes, credential rotation) need a restore point first (R13, ADR 0004). The VM has nested virtualization exposed, and the host can sleep while the VM runs.

Measured 2026-10-06:
- Checkpoint `post-install` was taken by `scripts/hyperv/New-PveHost.ps1:580` while the VM was Off, right after the unattended install; a second checkpoint, `pre-ansible-2`, was taken outside the setup script while the VM was Off (`Get-VMSnapshot` state `Off`).
- After restoring `post-install` and starting the VM, SSH answered in 16 s on both restores; the other cold starts were 18.1 s (first boot after install) and 15.9 s (after the 9.2 upgrade). A full Ansible baseline from the restored state took 254 s.
- During one run the host went into standby and suspended the VM with it, so the state of a running VM is not a point to rely on.

Documented (https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/manage/choose-between-standard-or-production-checkpoints-in-hyper-v): a standard checkpoint takes a snapshot of the VM and its memory state; a production checkpoint uses the Volume Shadow Copy Service, or a file system freeze on a Linux VM, and takes no memory state; with type `Production` a failed production checkpoint becomes a standard one, and type `ProductionOnly` does not. The VM here has type `Standard` (`scripts/hyperv/New-PveHost.ps1:382`).

Inferred, not documented: memory state can hold guest secrets in clear; a Linux freeze needs the Hyper-V backup daemon running in the guest, and whether this guest runs it is unknown.

Measured 2026-10-06: the three disk files of the VM total 17.67 GiB for a 5.9 GiB install, with 143.5 GiB free on the host drive. Inferred: each checkpoint freezes the current layer and starts a new one that can grow to the full 128 GiB.

## Options considered

1. Checkpoints of a running VM — no downtime; a standard checkpoint writes memory (with secrets) to disk, a production checkpoint depends on the integration service in the guest, with type `Production` a failed freeze silently becomes a standard checkpoint with memory (only `ProductionOnly` refuses), whether the guest runs the backup daemon is unknown, and the result for a nested-virtualization guest was never measured.
2. `Export-VM` copies — a self-contained copy that survives loss of the VM folder; needs the disk size in free space for every copy and time proportional to the disk, and the export is a second full copy of the guest disk and every secret on it (https://learn.microsoft.com/en-us/powershell/module/hyper-v/export-vm).
3. No restore points — nothing to keep; any failed upgrade or rotation means a reinstall (459 s unattended, then the rest of the setup).
4. Checkpoints taken only while the VM is Off, through one script action — no memory state exists, so nothing secret beyond the disk is written; costs a stop and a start (about 16 s to SSH) per restore point.

## Decision

Use option 4. `Invoke-PveVm.ps1 -Action Checkpoint -Name <name>` takes the checkpoint and refuses unless the VM is `Off`, the name is unused and valid, and no DVD drive holds media. Before the checkpoint it re-reads the VM state; after it, it reads the checkpoint back and requires state `Off` and no media in its recorded DVD drives, otherwise it removes that checkpoint and exits 1. It refuses when current free space on the VM's drive is below `MinFreeDiskAfterGrowthGiB` and warns when the worst case (free space minus the disk size) is below it. It runs non-elevated for a member of Hyper-V Administrators (ADR 0014). There is no restore action in the script; restore uses Hyper-V Manager or `Restore-VMSnapshot`.

## Rationale and trade-offs

- An Off VM has no memory state to write, and a host standby cannot suspend it (measured: standby suspended a running VM). The measured restore (16 s to SSH, 254 s to a full Ansible baseline) is short enough that stopping the VM per restore point is cheap.
- The refusal on attached media keeps the installer ISO, which holds the root-password hash, out of the VM configuration a checkpoint records, so a restore cannot re-attach it.
- Accepted cost: a restore point needs the VM stopped, so work that must keep the VM running cannot be protected by one. A checkpoint is also not a backup: it lives beside the VHDX and is lost with it.
- Disk: the measured chain is 17.67 GiB with two checkpoints (2026-10-06). The worst case for one more layer is free space minus 128 GiB, which is 15.5 GiB at 143.5 GiB free and below the 20 GiB floor, so the action warns rather than refuses; remove a checkpoint once the step it protects is verified. Not measured: merge time, and the cost of option 2 on this disk.
- Credential rotation: a checkpoint taken before a rotation still holds the old secrets on its frozen disk layer (inferred from how differencing disks work), and restoring it makes them live again. Take a fresh checkpoint after every rotation and remove the older ones; after a restore that crosses a rotation, rotate again before the VM is reachable.
- After a restore, start the VM only through `-Action Start`, which re-syncs the port ACLs before `Start-VM`. HYPOTHESIS: the restored configuration carries the port ACLs from checkpoint time; unmeasured.
- Revisit when the VM holds data worth more than a reinstall, when backup storage exists (Phase 7, Observability and resilience, in the platform plan), or when a running-VM checkpoint of a nested guest has been measured.
