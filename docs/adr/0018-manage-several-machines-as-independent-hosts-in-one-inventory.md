# 0018. Manage several machines as independent hosts in one inventory

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: D16, D15 in docs/platform/requirements.md (requirements R5.1, R10)

## Context

"Several machines" has to cover Proxmox hosts, rented VPSs and plain Linux machines, and the platform is meant to be taken to other hosts later (R10). Today there is exactly one machine, a laptop running Proxmox as a nested guest. Runner registration on a personal account is per repository, and a token needs Administration permission for that repository (`scripts/proxmox/ephemeral/homelab-ephemeral-runner.sh:47`), so the set of repositories served decides the token's reach.

The tree has the pieces of a per-host layout: one host config file with a `-ConfigPath` switch for another host (`scripts/hyperv/README.md`, file table, `pve01.psd1` row), one secrets file per host (`iac/secrets/hosts/pve01.sops.yaml`, selected by the path rule in `.sops.yaml:2`), and an Ansible inventory with host groups (`iac/ansible/inventory/hosts.ini.example`, removed, ADR 0020).

## Options considered

1. A Proxmox cluster — shared configuration and live migration, but a cluster cannot be formed on one machine, ties every member to Proxmox, and does not describe a VPS or plain Linux host.
2. Independent hosts in one inventory — each host is a record, the roles and workflows are shared, no host depends on another.
3. Host names and repository lists written into code or workflow files — nothing extra to configure, but every added host or repository is a code change.

## Decision

Option 2. Hosts are independent and listed in one inventory; adding a host is a data change, not a code change (R5.1).

- One OpenTofu stack type per purpose is instantiated per host, and one secrets file exists per host.
- Hypervisor-specific code sits behind an adapter boundary; roles for runner, cache and controller, the controller core and the workflows stay provider-neutral (R10).
- The repositories served are configuration (D15). The value today is this repository only. This is the narrowest token that works; adding a repository means widening the token, which is a deliberate act.

## Rationale and trade-offs

- A cluster is impossible on the one machine that exists, so independence is the only option that works today and also the one that fits VPS and on-prem targets.
- Accepted loss: no shared control plane, no live migration, no HA between hosts. Each host is rebuilt from code instead.
- Not proven yet: an inventory with a second, plan-only host, and the same roles converging on a GitHub-hosted Ubuntu VM with a runner registered from there running a job green (R10). A WSL Debian distro does not count as that proof, because it shares the Windows kernel and has no systemd by default. Until those runs exist, portability is HYPOTHESIS.
- Revisit if two or more Proxmox hosts need shared storage or migration, which is a different decision and not a reason to restructure the inventory.
