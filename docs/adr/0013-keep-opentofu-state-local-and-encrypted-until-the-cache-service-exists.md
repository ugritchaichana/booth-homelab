# 0013. Keep OpenTofu state local and encrypted until the cache service exists

- Status: Accepted
- Date: 2026-10-06
- Deciders: operator
- Decision log: D41 in docs/platform/requirements.md

## Context

The tree still carries an S3 backend pointing at a MinIO endpoint (`iac/tofu/backend.tf:9`, `http://10.99.20.20:9000`). That endpoint belonged to the previous Proxmox host, which is retired, so the backend has nothing to talk to. The new S3-compatible cache service is planned for Phase 4 and does not exist yet.

State files hold provider credentials and generated secrets in plain JSON. R4 asks for state with locking, and the repository is public, so state must never be readable if a copy leaks.

## Options considered

1. Keep the MinIO S3 backend — remote and locked, but its endpoint no longer exists, and rebuilding it first would make the cache service a prerequisite of the IaC foundation.
2. Local backend, unencrypted — works immediately and the local backend locks its state file, but every copy of the file exposes every secret in it.
3. Local backend with OpenTofu state encryption enforced — works immediately, locks the state file, and a leaked copy is ciphertext.

## Decision

Use option 3 until the cache service exists, then move to an S3 backend with `use_lockfile` (needs OpenTofu 1.10 or later; the pinned version is 1.13.1).

- State lives in WSL on the ext4 filesystem, not under `/mnt/c`, because file locking on the Windows mount is assumed unsafe (HYPOTHESIS, not measured).
- Encryption uses a `pbkdf2` key provider with the `aes_gcm` method, with `enforced = true` for both state and plan, so OpenTofu refuses to write plaintext. Reference: https://opentofu.org/docs/language/state/encryption/.
- The passphrase is at least 32 random bytes, stored in a SOPS-encrypted file in the repository (key handling: ADR 0010).
- An encrypted copy of the state is written to the Windows profile before each apply, as a recovery point.

## Rationale and trade-offs

- The decision removes the dependency on a service that does not exist and keeps secrets encrypted at rest. The measured fact behind it is that the only configured backend points at a retired host.
- Named partial: the requirement "remote state" is not met until Phase 4; locking is exercised on the local file only. The migration is `tofu init -migrate-state` to the new backend, with the encryption block kept.
- Losing the passphrase loses the state. The passphrase is recoverable only through the single age key, so the owner's off-machine backup of that key is part of this decision (ADR 0010).
- State is on one machine, so there is no concurrent writer across hosts; this is acceptable only while one operator applies from one workstation.
- The stack that implements this decision lands in a later Phase 2 change; the backend file above is the state it replaces.
