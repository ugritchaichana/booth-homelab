# 0039. Keep templates as Proxmox templates on local-lvm, clone them linked and check clone origins before deleting one

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D67 in docs/platform/requirements.md

## Context

Runner guests are short-lived clones of a golden template (ADR 0016), so clone time and disk use decide the scale-up budget. The host has `local-lvm` (an LVM-thin pool named `data` in volume group `pve`, about 62 GiB, nothing on it at the end of Phase 2) and `local` (a directory store with about 34 GiB free).

Two facts from the installed storage code decide retention. Both were read in the upstream `pve-storage` sources and are re-checked against the installed files in the host proof:

- `PVE/Storage.pm`, in `vdisk_free`, guards deletion of a base volume with `volume_is_base_and_used`, and the note above that function says the check does not work for LVM-thin, where the clone-to-base reference is not encoded in the volume ID. The code comment in `vdisk_free` says LVM-thin allows deletion of still referenced base volumes.
- `PVE/Storage/LvmThinPlugin.pm` says in its header that deleting such a base leaves the linked clones working, and creates a clone with `lvcreate -s` of the base, a thin snapshot.

So Proxmox does not refuse to delete a template that has linked clones on this storage, and it cannot show the dependency either.

## Options considered

1. Proxmox templates on `local-lvm`, runner guests as linked clones (`full = false`), with the pipeline's own origin check before any delete.
2. A backup archive per version and a container created from it for every runner — no hidden dependency and retention is a file delete, but every start extracts the whole archive onto a thin volume, against a 30 second scale target, and deleting a file still needs a privilege the provisioner token lacks.
3. Full clones of a template — no dependency, but every clone copies the disk.

## Decision

Option 1.

- Templates are Proxmox templates (`template: 1`) of class `lxc-runner` and `vm-docker` on `local-lvm`. Consumers clone them linked. The clone's thin volume has the template's `base-<vmid>-disk-N` volume as its `origin`.
- Before deleting a version the orchestrator runs `lvs --reportformat json -o lv_name,origin,data_percent,metadata_percent pve` and refuses to delete a template when any volume has an origin that starts with `base-<vmid>-disk-`. The refusal is journaled and the version stays; the next build retries.
- Retention keeps exactly two versions per class: `current` and `previous`, as recorded in the root state (ADR 0040), not the two highest numbers. A rollback followed by a build therefore keeps the rollback target. Every other verified version, and every template in the class block that is not a verified version, is deleted only after the origin check finds no dependent volume.
- A guest counts as a version only when it is a template, carries the marker, class and `v<N>` tags and has a root-state entry written after its verification passed. A leftover non-template guest in the class block (a crashed build) is never a version: the next build stops and destroys it first.
- One build at a time, by a lock file in the state directory.
- A build is refused before anything is created when the thin pool `data_percent` or `metadata_percent` is above its threshold, or free space on `local` is below its threshold. Thin-pool metadata is checked because a full metadata volume stops writes with free data blocks left. The thresholds are role variables (`pve_templates_thresholds`) and are placeholders until the host proof measures a build; the numbers in the role are not measurements.
- Verification of a new version: a linked clone (`full = 0`) is created in the class block, checked on the host without starting it (not a template, one NIC on the guest vnet with its firewall on, no forbidden key, no `sshkeys`, `ipconfig*` or `cicustom`, and a thin volume whose origin is the new template), handed to the optional class hook (ADR 0038), and destroyed. A failed verification destroys the new template and promotes nothing.

## Rationale and trade-offs

- A linked clone is one `lvcreate -s`, a metadata operation, so it fits the scale target; the cost is the invisible dependency, which the origin check turns into a rule the pipeline can enforce.
- A clone that outlives its deleted template keeps working, so the gap between the origin check and the delete costs availability of a rollback target, not a broken guest. The lock closes the gap against the pipeline's own runs; another actor creating a clone in that window is the case the plugin header covers.
- Deleting a base frees no space while clones share its blocks, and migrating a thin volume copies the shared data. Both are measured in the host proof, not assumed here.
- Disk per version, clone time and build time are not measured in this change; the thresholds say so.
- The structural verification does not run anything inside a clone. That is deliberate: the build guest's SSH channel is closed before conversion (ADR 0038), and the class changes add the started-clone checks.
- `tests/isolation/test-template-build.sh` pins the cases: rollback then build keeps the rollback target, a version with a dependent volume is kept, a leftover is destroyed and not counted, a thin pool over either threshold or low `local` space refuses the build, and a full clone fails verification.
