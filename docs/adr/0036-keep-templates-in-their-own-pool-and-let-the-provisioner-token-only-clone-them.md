# 0036. Keep templates in their own pool and let the provisioner token only clone them

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D64 in docs/platform/requirements.md
- Refines: ADR 0026

## Context

Phase 3 builds golden templates and Phase 5 clones runner guests from them. A clone needs `VM.Clone` on the source guest, `VM.Allocate` on the target pool, `Datastore.AllocateSpace` on the storage and `SDN.Use` on the vnet. The provisioner token holds the last three (ADR 0026) and lacks `VM.Clone`.

Two facts decide where the privilege goes, both read from the installed PVE API code and the ADR 0026 roles:

- The guest role on `/pool/homelab` holds `VM.Allocate` and `VM.Config.Options`. Destroying a guest needs `VM.Allocate`, and setting tags needs `VM.Config.Options`. A template inside that pool can therefore be deleted or retagged by whoever holds the token, and a "current" marker kept as a tag could be moved onto any guest, a running runner included.
- `VM.Clone` on `/pool/homelab` would let the token clone any pool guest, running runners included, which yields a disk copy it can boot with its own key (HYPOTHESIS for a running source, not measured).

## Options considered

1. Grant `VM.Clone` to the guest role on `/pool/homelab` and keep templates there — one role fewer, but the token can clone running runners and delete or retag templates.
2. A separate consumer token holding `VM.Clone` — adds a second secret file and a second provider alias without shrinking the provisioner token, which already creates and destroys guests, and the templates still need a pool the provisioner token cannot delete from.
3. A dedicated pool `templates` and a role `HomelabTemplateClone` of exactly `VM.Clone` and `VM.Audit`, granted on `/pool/templates` to the existing provisioner user and token.

## Decision

Option 3, implemented in `iac/ansible/roles/pve_api_identity`.

- The role creates the pool `templates` next to `homelab` and grants `HomelabTemplateClone` on `/pool/templates` to the user and the token, as one more entry of the declared grants. The existing check that the identity holds exactly the declared grants, for the user and for the token, therefore covers it.
- Two assertions run on every converge and in CI (`tests/isolation/test-pve-api-identity-grants.sh`): `VM.Clone` appears in no role granted on any path except `/pool/templates`, and the roles granted on `/pool/templates` hold nothing beyond `VM.Clone` and `VM.Audit`. `VM.Clone` is not added to the forbidden privileges, because the new role holds it on purpose.
- Templates join the pool only after their build verification passes; a build guest joins no pool. Runner clones land in `homelab` through the clone call's `pool` parameter.
- Without `VM.Allocate` or `VM.Config.Options` on the templates pool, the token can clone a template but cannot delete it or change its tags. Moving the "current" marker stays a root-only action.

## Rationale and trade-offs

- The pool split is what removes delete and retag. A separate token would not: the provisioner token would still hold `VM.Allocate` on every pool it can reach.
- The Phase 5 controller token gets the same role, so one role serves both consumers.
- HYPOTHESIS, settled by the host proof: that a pool ACL satisfies the `VM.Clone` check on a template's own path (`/vms/<vmid>`). The proof is, with the provisioner token, a clone returning 200 while DELETE and a tag PUT on the template return 403. If cloning also needs `Datastore.Audit` on the template's storage, the token already holds it on `local-lvm`.
- The assertions read the declared variables, so they prove the declaration, not the live ACLs; the live check is `pveum acl list` on the host.
- Not done here: moving any guest into the pool, the consumer lookup that fails closed unless exactly one template matches, and the build pipeline. They are separate changes.
