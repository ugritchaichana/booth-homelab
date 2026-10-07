# 0026. Bootstrap the OpenTofu API identity with Ansible and keep its token in SOPS

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D48 in docs/platform/requirements.md

## Context

The identity that runs OpenTofu cannot be created by the OpenTofu run that needs it. Automation must never use the root password (R5.3), and the Proxmox web console cannot be scripted or reviewed.

Measured from the host's apidoc (`host-facts` section 13, 2026-10-06): the privileges the planned guest and SDN work needs are `SDN.Allocate`, `SDN.Audit`, `SDN.Use`, `Datastore.AllocateTemplate`, `Datastore.AllocateSpace`, `VM.Allocate`, `VM.Audit`, `VM.Config.Network`, and `Sys.AccessNetwork` on the node for template downloads (the endpoint accepts it instead of `Sys.Modify` on `/`). Read from the installed `API2/Qemu.pm`, `API2/LXC.pm` and `Storage.pm` on 2026-10-07: guest create and change also check `VM.Config.{CPU,Memory,Disk,Options,Cloudinit,HWType}` and `VM.PowerMgmt`; reading a template or import volume needs `Datastore.Audit` or `Datastore.AllocateSpace` on its storage (`Storage.pm`, `check_volume_access`); `VM.Config.CDROM` is checked only for CD-ROM media, which the probe guests do not use (HYPOTHESIS until the first apply). Permissions on a deeper path replace those inherited from a higher one and `NoAccess` cancels every other role on its path (https://pve.proxmox.com/pve-docs/chapter-pveum.html, section on permission inheritance). `pveum` on the host takes `--privsep` for tokens and `--users` plus `--tokens` in one ACL call.

## Options considered

1. OpenTofu creates its own user and token with root credentials — one tool, but the root password or root token enters the automation path.
2. Create the user and token by hand in the console — nothing to review and no way to rebuild.
3. Ansible creates the user, role, pool, ACLs and a privilege-separated token, and stores the secret in a SOPS file that only that role writes.

## Decision

Option 3, implemented by `iac/ansible/roles/pve_api_identity`.

- User `tofu@pve` without a password, so it cannot log in; pool `homelab`; never `Permissions.Modify`, `User.Modify` or `Sys.Modify` (the role asserts this).
- One role per purpose, each granted only on its path: guests (`VM.Allocate`, `VM.Audit`, `VM.Config.{CPU,Cloudinit,Disk,HWType,Memory,Network,Options}`, `VM.PowerMgmt`) on `/pool/homelab`; `Datastore.AllocateSpace` and `Datastore.Audit` on `/storage/local-lvm` (the first probe apply measured an HTTP 403 "Datastore.Audit on /storage/local-lvm" when the provider read the new VM disk's volume info); `Datastore.AllocateTemplate` and `Datastore.Audit` on `/storage/local`; `Sys.AccessNetwork` on the node; `SDN.Allocate` and `SDN.Audit` on `/sdn`; `SDN.Use` only on the guest vnet, together with `SDN.Allocate` and `SDN.Audit` there, because a deeper grant replaces the one from `/sdn` and the network stack still manages that vnet's subnet; and `NoAccess` on `/sdn/zones/localnetwork`, so no guest can be attached to `vmbr0` and the network stack cannot change it. A new vnet created by the token carries no `SDN.Use`, so no guest can use it.
- The roles are granted to both the user and the token. A privilege-separated token holds the intersection of its own ACLs and its user's, so granting only the token leaves it with nothing. The role removes any grant of the identity that is not declared (including the earlier single-role grants and that role), then asserts the user and the token hold exactly the declared grants.
- The token `provisioner` is created once. Its secret goes into `iac/secrets/tofu/<host>-api.sops.yaml` with `sops set --value-stdin`, never on a command line and never in a log (`no_log`). A run skips an existing token and fails if the stored secret is missing; `-e pve_api_identity_rotate=true` replaces it. If storing the secret fails, the new token is removed so the next run can create it again.

## Rationale and trade-offs

- Measured 2026-10-07 in a scratch directory with a throwaway age key: `sops set --value-stdin` needs an existing file and a JSON-encoded value (an unquoted value fails with `Value for --set is not valid JSON`); a file created with `sops encrypt --filename-override` then given a secret by stdin decrypted to a 36-character value.
- Kept on purpose: `Datastore.AllocateTemplate` and `Sys.AccessNetwork`, because the probe stack downloads its VM image with the provider's download call, which needs both (apidoc, `host-facts` section 13). They let the token holder make the host fetch a URL; moving downloads to Ansible would remove them.
- Accepted loss: the one token still holds `SDN.Allocate` on `/sdn` for the network stack, so a leaked token can change SDN. A second token for the network stack is the follow-up; the roles are already split for it. The token can also change a guest's firewall settings (`VM.Config.Network` has no finer split), which is why ADR 0027 adds a root-owned detector.
- Not proven until the first apply: that a grant on a vnet path that does not exist yet is accepted, and which `VM.Config.*` a real plan still lacks; the roles in `defaults/main.yml` are the only place to change.
- Accepted loss: the secret value passes through controller memory and the Ansible module payload directory for the length of one task.
- The token's inability to create users or ACLs (HTTP 403) is proven at the first converge, not by this record.
- A pool-scoped token must not set guest tags at create time: Proxmox checks `VM.Config.Options` for tags on `/vms/<id>` without the pool, which a guest that does not exist yet cannot inherit from the pool (measured on the first probe apply: 403 on both creates).
