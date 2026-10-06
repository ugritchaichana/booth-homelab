# 0005. Use the no-subscription repository and upgrade through Ansible

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D31, D40 in docs/platform/requirements.md

## Context

A fresh Proxmox VE install points at the enterprise package repository, which needs a paid per-socket subscription; without one the package index fails and the UI shows a nag. The install media is 9.1-1 (ADR 0004), so the host must be upgraded to the latest 9.x. An upgrade done by hand once is not reproducible, and R4 requires idempotent configuration with Ansible.

## Options considered

1. Enterprise repository with a subscription — most tested updates and support; a recurring cost for a personal lab (price not checked).
2. `pve-no-subscription` repository — free, the same packages with less testing, plus a UI notice; documented at https://pve.proxmox.com/wiki/Package_Repositories.
3. Switch the repositories and upgrade ad hoc during the install phase — fastest now; leaves no code and no proof of repeatability.

## Decision

Use `pve-no-subscription` and disable the enterprise repository (owner, D31). Do the repository switch, `apt full-upgrade` and the reboot as the first Ansible role of the infrastructure phase (D40). The nested-KVM smoke test runs on the installer kernel and again after the upgrade. The install-phase definition of done (`pveversion` 9.x, nested result) does not depend on the upgrade.

## Rationale and trade-offs

- The owner picked the free repository for a single-host homelab. Accepted cost: updates are less tested than the enterprise stream, and the web UI keeps a notice about the missing subscription.
- A role that a second run reports as `changed=0` is the proof of repeatability (R4); an ad hoc command would be unproven.
- The role exists in #59 (stacked on #58): `iac/ansible/roles/pve_repos/tasks/main.yml` disables the pve-enterprise and Ceph enterprise repositories, enables `pve-no-subscription` as deb822, runs the full upgrade, and reboots only on a marker or a newer kernel. It is run by `iac/ansible/playbooks/pve-baseline.yml` against `iac/ansible/inventory/pve01.yml`, which reaches the host through the ProxyCommand hop (ADR 0011).
- Measured 2026-10-06 (#59): pve-manager 9.1.1 to 9.2.21 and kernel 6.17.2-1-pve to 7.0.14-20-pve; 0 pending upgrades afterwards; a second run reports `changed=0`. Before the upgrade the nested-KVM result was `kvm_amd nested` = 1, `svm` 12 on the installer kernel (#58); after it, on 7.0.14, the smoke test still passes (`svm` 12, `/dev/kvm` present, `nested` = 1).
- Open, UNVERIFIED in #59: on the first attempt the Ansible process never received the result of the long upgrade through the proxy hop, although the upgrade itself finished. Async with polling and keep-alives were added to the role; they have not yet been exercised on a long upgrade.
- Revisit if the host starts carrying workloads that need the enterprise stream's testing, or if the owner takes a subscription.
