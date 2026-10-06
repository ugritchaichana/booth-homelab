# Architecture decision records

An architecture decision record (ADR) states one decision, the options that were weighed, the choice, and why it won, including what was given up and what was measured. The decision log in `docs/platform/requirements.md` keeps one short row per decision; the ADR holds the reasoning so that someone adapting this repository to another host can see which choices were forced by this machine and which were taste.

## Rules

- One decision per ADR.
- Numbers are four digits and are never reused, even for a withdrawn record.
- To change a decision, write a new ADR and add "Superseded by NNNN" to the old one's status line. Do not rewrite history in the old file.
- Each pull request that finalizes a decision adds its ADR. Decisions still open get no ADR until they are decided.
- File name: `NNNN-<kebab-of-title>.md`. Kebab rule: lowercase the title, replace every run of non-alphanumeric characters with a single hyphen, trim hyphens at the ends (`9.1` becomes `9-1`, `Hyper-V` becomes `hyper-v`, commas are dropped).
- Keep each record to about 25 to 60 lines. Facts only; cite a `path:line`, a pull request, a measured value, or a documentation URL.
- Artifacts are English and neutral (ADR 0002): no organization, person, or vendor names, no host or network identifiers beyond the lab ranges in configuration.

## Template

```
# NNNN. <short imperative title>

- Status: Accepted
- Date: YYYY-MM-DD
- Deciders: owner | operator | owner and operator
- Decision log: D<n>[, D<m>] in docs/platform/requirements.md

## Context
<problem, forces, constraints; measured facts and file:line>

## Options considered
1. <option> — <pro / con>
2. <option> — <pro / con>
3. <option> — <pro / con>

## Decision
<the chosen option, plainly>

## Rationale and trade-offs
<why it beat the others; what is accepted as lost; measured evidence; residual uncertainty labelled HYPOTHESIS; when to revisit>
```

## Index

| Number | Title | Status |
|---|---|---|
| 0001 | [Record architecture decisions](0001-record-architecture-decisions.md) | Accepted |
| 0002 | [Keep the repository neutral and English-only](0002-keep-the-repository-neutral-and-english-only.md) | Accepted |
| 0003 | [Host Proxmox VE as a nested Hyper-V guest on the workstation](0003-host-proxmox-ve-as-a-nested-hyper-v-guest-on-the-workstation.md) | Accepted |
| 0004 | [Install Proxmox VE 9.1 unattended from a prepared ISO](0004-install-proxmox-ve-9-1-unattended-from-a-prepared-iso.md) | Accepted |
| 0005 | [Use the no-subscription repository and upgrade through Ansible](0005-use-the-no-subscription-repository-and-upgrade-through-ansible.md) | Accepted |
| 0006 | [Isolate the VM behind an internal switch and WinNAT](0006-isolate-the-vm-behind-an-internal-switch-and-winnat.md) | Accepted |
| 0007 | [Enforce a host-side isolation layer with Hyper-V port ACLs](0007-enforce-a-host-side-isolation-layer-with-hyper-v-port-acls.md) | Accepted |
| 0008 | [Keep Proxmox off the tailnet and reach the UI through the host](0008-keep-proxmox-off-the-tailnet-and-reach-the-ui-through-the-host.md) | Accepted |
| 0009 | [Store secrets with SOPS and age in the repository](0009-store-secrets-with-sops-and-age-in-the-repository.md) | Accepted |
| 0010 | [Run the operator toolchain in WSL with pinned, verified binaries](0010-run-the-operator-toolchain-in-wsl-with-pinned-verified-binaries.md) | Accepted |
| 0011 | [Reach Proxmox from WSL through an SSH ProxyCommand on the Windows host](0011-reach-proxmox-from-wsl-through-an-ssh-proxycommand-on-the-windows-host.md) | Accepted |
| 0012 | [Use OpenTofu and Ansible for infrastructure as code](0012-use-opentofu-and-ansible-for-infrastructure-as-code.md) | Accepted |
| 0013 | [Keep OpenTofu state local and encrypted until the cache service exists](0013-keep-opentofu-state-local-and-encrypted-until-the-cache-service-exists.md) | Accepted |
| 0014 | [Run host setup in one elevated pass that never reboots, with the owner in Hyper-V Administrators](0014-run-host-setup-in-one-elevated-pass-that-never-reboots-with-the-owner-in-hyper-v-administrators.md) | Accepted |
| 0015 | [Run Docker workloads in VMs, never in privileged containers](0015-run-docker-workloads-in-vms-never-in-privileged-containers.md) | Accepted |
| 0016 | [Scale CI with an ephemeral runner pool and overflow to hosted runners](0016-scale-ci-with-an-ephemeral-runner-pool-and-overflow-to-hosted-runners.md) | Accepted |
| 0017 | [Size templates by generic cloud flavors](0017-size-templates-by-generic-cloud-flavors.md) | Accepted |
| 0018 | [Manage several machines as independent hosts in one inventory](0018-manage-several-machines-as-independent-hosts-in-one-inventory.md) | Accepted |
| 0019 | [Take restore points of the PVE VM only while it is Off](0019-take-restore-points-of-the-pve-vm-only-while-it-is-off.md) | Accepted |
| 0020 | [Retire the bootstrap, cache and Ansible assets of the previous host instead of porting them](0020-retire-the-bootstrap-cache-and-ansible-assets-of-the-previous-host-instead-of-porting-them.md) | Accepted |
