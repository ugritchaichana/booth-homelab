# 0059. Open the reference lab to visitors

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D91 and D92 in docs/platform/requirements.md

## Context

The owner wants other people to try the proof of concept easily: open pull requests that run CI, log in to the Proxmox web UI, and look inside any machine without being able to change it. Two settings stood in the way:
- Fork pull requests from external contributors waited for approval. The setting was "all external contributors", set earlier the same day (D89).
- Every machine had a root password nobody could share. The host's was a generated secret, and the guests' root accounts were locked.

What protects the lab while it is open:
- No self-hosted runner is registered (runners API `total_count=0`). The caller workflow forces hosted runners on push and pull_request (`.github/workflows/sdet-ci.yml:28`), and a fork pull request receives no repository secrets.
- `master` requires one approving review from a code owner. The code owner is the repository owner (`.github/CODEOWNERS`), a new push dismisses stale approvals, and the owner is the only collaborator. A visitor's pull request runs CI but merges only with the owner's approval.
- The web UI is reachable only through the workstation's tailnet relay (ADR 0008). SSH on `pve01` refuses passwords (`passwordauthentication no`, `permitrootlogin without-password`).
- The R15 host-side layer (switch port ACLs and the Windows firewall rule, outside the VM) keeps `pve01` and its guests away from the LAN and the workstation. Guest-stack VMs drop all inbound traffic (`policy_in: DROP`).

## Options considered

1. Keep both controls as they are.
2. Loosen fork approval as far as GitHub allows, give every machine the same two accounts (a root account and a read-only visitor account), and keep the merge review.
3. A shared root password only, with no visitor account. The owner asked for this first, then chose option 2.

## Decision

Option 2.

- Fork pull-request approval is `first_time_contributors_new_to_github`, the loosest value the API accepts. No value turns approval off.
- Every machine gets the same two accounts with the same passwords:
  - **Root.** On the host, `root@pam` (web UI realm "Linux PAM"). On each guest, the local root account.
  - **Visitor, web UI.** `guest@pve` (realm "Proxmox VE authentication server") with role `LabGuest`, granted on `/`. The role holds the `PVEAuditor` privileges plus `VM.Console`.
  - **Visitor, inside each guest.** A local user `guest` that belongs to no administrative group (`sudo`, `wheel`, `adm`, `docker`, `lxd`, `disk`).
- The passwords live only in SOPS: `root_password` in `iac/secrets/hosts/pve01.sops.yaml`, `guest_password` in `iac/secrets/hosts/pve01-lab-accounts.sops.yaml`. Neither appears in this repository in plain text.
- `iac/ansible/playbooks/lab-accounts.yml` applies them:
  - on the host;
  - in every running container, through `pct exec`;
  - on the R15 probe VM, over its control key;
  - on guest-stack VMs, through a cloud-init vendor snippet. These VMs accept no inbound connection, so the snippet's `bootcmd` sets the accounts at every boot. `runcmd` runs once per instance and was skipped on an existing VM.
- Merges keep the code-owner review on `master`.

## Consequences

- Accepted risk:
  - Anyone with the root password and access to the owner's tailnet is root on `pve01` and on every guest.
  - Traffic from the VM leaves through the workstation's NAT, so it appears to come from the owner's network.
  - The visitor can open consoles, and so can send Ctrl-Alt-Del to a VM.
  - The visitor can read world-readable files inside a guest.
  - On a container whose SSH daemon accepts passwords, the visitor can also log in over SSH, but only from inside the lab network.
- Fork pull requests must not reach the first self-hosted runner (Phase 5 entry gate 1). Before it registers, do one of these: route forks to hosted, restore approval for all external contributors, or reject fork events in a runner job-start hook. A fork can name a self-hosted label in its own workflow file.
- Templates keep root locked and have no visitor account:
  - a new container gets the accounts when the playbook runs again;
  - a new guest-stack VM gets them at its first boot if its `guests.yml` entry names `vendor_snippet`;
  - a password change reaches a guest-stack VM at its next boot.
- An adopter replaces both passwords before the host holds anything of value or anyone untrusted can reach the UI (runbook 3.5), and decides on login hardening by ADR 0058.
