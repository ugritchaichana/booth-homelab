# 0058. Keep Proxmox login hardening off in the reference lab and document it for adopters

- Status: Accepted
- Date: 2026-10-08
- Deciders: owner
- Decision log: D90 in docs/platform/requirements.md (supersedes the TOTP part of D60)

## Context

This repository is a proof of concept and a learning project, and a base that others adapt for personal, workplace or shared use. A second factor on the Proxmox web UI adds a step to every login and a recovery procedure to every setup, for every reader who builds the lab.

What already protects the web UI in this lab:
- PVE is not on the tailnet (D20). The UI is reached only through the Windows host: a `tailscale serve` TCP forward to a loopback `portproxy` (ADR 0008).
- `root@pam` is break-glass only, over an SSH key from the management address; no automation uses it ([architecture.md](../handoff/architecture.md), identities). OpenTofu authenticates with an API token (`iac/tofu/stacks/guest/providers.tf:1`) and Ansible with an SSH key.
- The root password lives only in `iac/secrets/hosts/pve01.sops.yaml`, encrypted with SOPS and age.

## Options considered

1. Enrol TOTP on `root@pam` now. Every UI login needs the code; the owner keeps recovery keys; eight failed codes lock the TOTP factor until an administrator unlocks it.
2. Keep login hardening off in the reference lab, and document what to turn on, when and how.

## Decision

Option 2. TOTP on `root@pam` stays off in this lab. The adopter table in [security-model.md](../handoff/security-model.md) says when to turn it on, and these steps, read from the Proxmox VE 9.2 admin guide and CLI on `pve01`, say how:

1. Web UI, Datacenter → Permissions → Users: select the user, then the TFA button. Add TOTP: scan the secret with an authenticator app and type the current code into Verification Code.
2. Add one-time recovery keys (TFA type `recovery`) and store them outside the host, next to the age identity.
3. Check: `pveum user tfa list root@pam` lists the entries. An administrator clears a lockout with `pveum user tfa unlock <userid>`.

## Consequences

- Accepted risk: anyone who can reach the relay over the tailnet and holds the root password can log in to the UI. The tailnet's membership and the age identity are the controls that remain.
- Turn TOTP on before any of these: someone other than the owner can reach the UI; a second administrator joins; the host carries real workloads; the UI is exposed beyond the tailnet relay.
- Turning it on changes no automation in this repository: nothing logs in as `root@pam` (OpenTofu uses an API token, Ansible an SSH key).
- The notification target from D60 stays open and belongs to Phase 7.
