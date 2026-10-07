# 0041. Let the template role own base images, snippets content and the weekly rebuild

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D72 in docs/platform/requirements.md

## Context

The template framework (ADR 0038, 0039, 0040) builds a golden template per class from a base volume named in `iac/ansible/roles/pve_templates/defaults/main.yml` (`local:vztmpl/...` for the container class, `local:import/...` for the VM class). Nothing fetched those volumes, and they were deleted in an earlier teardown. ADR 0035 left the storage definitions as the installer made them and deferred an image owner to Phase 3. The R15 probe and the later runner bootstrap pass cloud-init vendor data to VM clones, which needs the `snippets` content type on `local`; the installer set `iso,vztmpl,backup,import`. Nothing scheduled a rebuild either.

## Options considered

1. OpenTofu downloads the images through `proxmox_download_file`, as the probe stack does — needs the provisioner token to write volumes, and the token must not delete volumes (ADR 0026, ADR 0035).
2. Ansible role `pve_templates` downloads the images as root on the host — no API token involved, the checksum pin fails the converge on mismatch, and the role already runs as root for the template build.
3. Fetch the images by hand when a build fails — no owner, no pin, and the failure shows up only when a build is needed.

## Decision

Option 2, together with two related duties of the same role:

- Base images: `ansible.builtin.get_url` with `checksum: sha512:<pin>` writes each class base image to its storage path as root (`/var/lib/vz/template/cache/` for the container template, `/var/lib/vz/import/` for the qcow2). URLs and pins are role defaults per class, copied from the probe stack. The API token does not touch images.
- Storage content: the role adds `snippets` to the existing content list of `local` with `pvesm set`, reading the current list first and asserting afterwards that nothing was lost. This refines ADR 0035 and D63: storage definitions stay installer-made, with this one content type added by Ansible.
- Rebuild schedule: a systemd timer (`OnCalendar=weekly`, `Persistent=true`, `RandomizedDelaySec=15min`) starts a service that builds every class in turn through the existing `homelab-template-build@<class>.service` unit, so `OnFailure=` is reused. A change of a class's deployed `versions.yml` starts that class's build at once without waiting.

## Rationale and trade-offs

- A missed run is caught up on the next boot because of `Persistent=true`; a timer that has never fired has no stamp, so enabling it does not trigger a build.
- Nothing in the schedule starts the PVE VM; the units run on the host itself, so D25 is unchanged.
- The weekly service tolerates a failing class (`ExecStart=-`) so one broken class does not block the others; the failure is recorded by the build unit's `OnFailure=` unit, not by the weekly service's exit status.
- Bumping a base image is a pin edit in the role defaults and a converge; a wrong pin fails the converge instead of building from an unverified image.
- The first converge with bundles present starts a build of every class, because every `versions.yml` is new on the host.
- Not measured: the time of a full weekly run of all classes; the weekly service timeout of 12 hours is a placeholder.
