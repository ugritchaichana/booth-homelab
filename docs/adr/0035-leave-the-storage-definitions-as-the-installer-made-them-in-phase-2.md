# 0035. Leave the storage definitions as the installer made them in Phase 2

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D63 in docs/platform/requirements.md

## Context

Recorded after the implementation, as a late record under the repository's rule that every decision gets an ADR. Implemented by #67 (the token's datastore grants), #68 (the OpenTofu host stack) and #71 (the R15 probe stack, which uses both storages, `iac/tofu/stacks/r15-probe/variables.tf:55-65`).

The Phase 2 plan line reads "OpenTofu for storage, network, users, tokens and ACLs". The installer already created the storages that every Phase 2 need uses: `local`, a directory storage with the content types `iso,vztmpl,backup,import`, and `local-lvm`, an LVM-thin storage for guest disks. The probe stack used both.

Measured in the installed PVE 9.2 API code:

- Creating, updating and deleting a storage definition checks `Datastore.Allocate` on `/storage` (`PVE/API2/Storage/Config.pm`).
- Deleting a volume needs `Datastore.Allocate` on the storage (`PVE/API2/Storage/Content.pm`, permission text "You need 'Datastore.Allocate' privilege on the storage").
- That privilege also deletes any volume on the storage, backups included.

## Options considered

1. OpenTofu manages the storage definitions — matches the plan line, but the token would need `Datastore.Allocate`, which conflicts with the least-privilege token of ADR 0026 because it can delete any volume, backups included.
2. Ansible asserts the storage shape — keeps the privilege on the root-owned path, but adds a role for definitions that nothing in Phase 2 changes.
3. Leave the storage definitions as the installer made them and let OpenTofu only read them — no new privilege and no new owner, at the cost of the teardown gap below.

## Decision

Option 3 for Phase 2. Phase 3 (images) and Phase 4 (cache) name an owner when they need a new storage.

## Rationale and trade-offs

- The measured fact behind the choice: the one privilege that manages storage definitions also deletes backups, so granting it to the token would weaken ADR 0026 for definitions that never change.
- Consequence, measured on the host on 2026-10-07: `tofu destroy` of the R15 probe stack removed every guest resource but returned 403 "Permission check failed (/storage/local, Datastore.Allocate)" for the two downloaded volumes.
- Accepted loss: teardown of the probe stack needs one operator `pvesm free <volid>` per downloaded file, after which `destroy` reconciles state. This is recorded as a known gap in the R15 probe PR (#71).
- Accepted loss: the storage layout is whatever the installer produced and is not reviewable as code until a later phase assigns an owner.
