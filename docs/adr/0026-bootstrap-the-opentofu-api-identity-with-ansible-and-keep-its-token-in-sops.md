# 0026. Bootstrap the OpenTofu API identity with Ansible and keep its token in SOPS

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D48 in docs/platform/requirements.md

## Context

The identity that runs OpenTofu cannot be created by the OpenTofu run that needs it. Automation must never use the root password (R5.3), and the Proxmox web console cannot be scripted or reviewed.

Measured from the host's apidoc (`host-facts` section 13, 2026-10-06): the privileges the planned guest and SDN work needs are `SDN.Allocate`, `SDN.Audit`, `SDN.Use`, `Datastore.AllocateTemplate`, `Datastore.AllocateSpace`, `VM.Allocate`, `VM.Audit`, `VM.Config.Network`, and `Sys.AccessNetwork` on the node for template downloads (the endpoint accepts it instead of `Sys.Modify` on `/`). `pveum` on the host takes `--privsep` for tokens and `--users` plus `--tokens` in one ACL call.

## Options considered

1. OpenTofu creates its own user and token with root credentials — one tool, but the root password or root token enters the automation path.
2. Create the user and token by hand in the console — nothing to review and no way to rebuild.
3. Ansible creates the user, role, pool, ACLs and a privilege-separated token, and stores the secret in a SOPS file that only that role writes.

## Decision

Option 3, implemented by `iac/ansible/roles/pve_api_identity`.

- User `tofu@pve` without a password, so it cannot log in; role `HomelabProvisioner` with exactly the measured privileges, never `Permissions.Modify`, `User.Modify` or `Sys.Modify` (the role asserts this); pool `homelab`.
- The role is granted to both the user and the token on `/sdn`, each storage, `/pool/homelab` and the node. A privilege-separated token holds the intersection of its own ACLs and its user's, so granting only the token leaves it with nothing. After granting, the role asserts the identity holds no other grant.
- The token `provisioner` is created once. Its secret goes into `iac/secrets/tofu/<host>-api.sops.yaml` with `sops set --value-stdin`, never on a command line and never in a log (`no_log`). A run skips an existing token and fails if the stored secret is missing; `-e pve_api_identity_rotate=true` replaces it. If storing the secret fails, the new token is removed so the next run can create it again.

## Rationale and trade-offs

- Measured 2026-10-07 in a scratch directory with a throwaway age key: `sops set --value-stdin` needs an existing file and a JSON-encoded value (an unquoted value fails with `Value for --set is not valid JSON`); a file created with `sops encrypt --filename-override` then given a secret by stdin decrypted to a 36-character value.
- HYPOTHESIS, not measured: guest creation also needs `VM.Config.Disk`, `VM.Config.CPU`, `VM.Config.Memory`, `VM.Config.Options`, `VM.Config.Cloudinit`, `VM.Config.HWType`, `VM.PowerMgmt`, `Pool.Audit` and `Datastore.Audit`. They are not added now; the first HTTP 403 from a real plan names the missing one and the list in `defaults/main.yml` is the only place to change.
- Accepted loss: the secret value passes through controller memory and the Ansible module payload directory for the length of one task.
- The token's inability to create users or ACLs (HTTP 403) is proven at the first converge, not by this record.
