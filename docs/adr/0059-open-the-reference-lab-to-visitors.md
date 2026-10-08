# 0059. Open the reference lab to visitors

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D91 in docs/platform/requirements.md

## Context

The owner wants other people to try the proof of concept easily: open pull requests that run CI, and log in to the Proxmox web UI to look around and experiment. Two settings stood in the way. Fork pull requests from external contributors waited for approval (set to "all external contributors" earlier the same day, D89). The root password was a generated secret known only to the owner.

What protects the lab while it is open:
- No self-hosted runner is registered (runners API `total_count=0`). The caller workflow forces hosted runners on push and pull_request (`.github/workflows/sdet-ci.yml:28`), and a fork pull request receives no repository secrets.
- `master` requires one approving review from a code owner, the code owner is the repository owner (`.github/CODEOWNERS`), stale approvals are dismissed on a new push, and the owner is the only collaborator. A visitor's pull request runs CI but merges only with the owner's approval.
- The web UI is reachable only through the workstation's tailnet relay (ADR 0008). SSH on `pve01` refuses passwords (`passwordauthentication no`, `permitrootlogin without-password`), so the root password opens the web UI and nothing else.
- The R15 host-side layer (switch port ACLs and the Windows firewall rule, outside the VM) keeps `pve01` and its guests away from the LAN and the workstation, whatever happens inside the VM.

## Options considered

1. Keep both controls as they are.
2. Loosen fork approval as far as GitHub allows, set a shared demo root password, and rely on the merge review and the network boundary.
3. As 2, but give visitors a separate limited Proxmox user instead of root. Offered to the owner, who chose root for simplicity.

## Decision

Option 2.

- Fork pull-request approval is `first_time_contributors_new_to_github`, the loosest value the API accepts; no value turns approval off.
- `root@pam` has a shared demo password that the owner gives to visitors. It is stored in `iac/secrets/hosts/pve01.sops.yaml` like any other value and is not written in this repository in plain text.
- Merges keep the code-owner review on `master`.

## Consequences

- Accepted risk: anyone with the demo password and access to the owner's tailnet is root on `pve01` and every guest, and traffic from the VM leaves through the workstation's NAT, so it appears to come from the owner's network.
- Before the first self-hosted runner registers (Phase 5 entry gate 1), fork pull requests must not reach it: route forks to hosted, or restore approval for all external contributors. A fork can name a self-hosted label in its own workflow file.
- An adopter replaces the demo password before the host holds anything of value or anyone untrusted can reach the UI (runbook 3.5), and decides on login hardening by ADR 0058.
