# 0009. Store secrets with SOPS and age in the repository

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D12, D23, D29, D42 (Q6, Q10) in docs/platform/requirements.md

## Context

Infrastructure code needs secrets (first the PVE root password, later API tokens and cache keys), and R13 requires every credential to be new and never printed. The same repository should move to a VPS or a fork by carrying one key (R10). The unattended install needs the root password from the first boot (ADR 0004), so the key store must exist before the install.

The workstation is used by the owner alone. A review on 2026-10-06 found a second, unused local administrator account; the owner accepted that every local administrator is inside the trust boundary (D42).

## Options considered

1. SOPS with age, files encrypted in the repository, plus GitHub secrets for CI — secrets travel with the code and are diffable by key name; one identity file must be protected and backed up.
2. Windows Credential Manager — nothing in git; tied to one Windows profile and not portable to a fork or Linux CI.
3. A password manager as the only store — good for people; not scriptable by the toolchain and not reviewable next to the code that uses it.

## Decision

Encrypt IaC secrets with SOPS for a single age recipient (`.sops.yaml:2-3`, rule `^iac/secrets/.*\.sops\.ya?ml$`). The age identity lives in the owner's Windows profile (`%APPDATA%\sops\age\keys.txt`) and is read from WSL through `SOPS_AGE_KEY_FILE`; it is generated locally before the install and never printed. The owner keeps an off-machine copy in a password manager (D29). CI secrets are set through the `gh` CLI and listed by name only. The ISO build renders the answer file in memory-backed `/dev/shm` and pipes the password straight into the hash step, with no shell variable (`scripts/proxmox/build-auto-install-iso.sh:85,119`).

## Rationale and trade-offs

- One identity makes a fork or VPS move a one-key change and keeps the secret file reviewable; the cost is a single point of loss: without the offline copy every secret is unrecoverable (`iac/secrets/README.md`, Recovery and rotation, first bullet).
- Rule learned, measured 2026-10-06: if the age identity is exposed, change the secrets; re-encrypting does not help, because old ciphertext stays in history and stays decryptable (`iac/secrets/README.md`, Recovery and rotation, second bullet). The first identity was exposed before any install, after its ciphertext of the root password was already in a public commit. Both the identity and the root password were replaced, a new recipient was set, and the ISO was rebuilt (`f70f3ac`). The old ciphertext remains in branch history but protects a password that was never used.
- ACLs on the key files limit non-administrator principals only; local administrators can read the key regardless (D42, accepted).
- gitleaks over the new commits found no leak (#58); the CI secret scan runs gitleaks too.
- Revisit when a second maintainer needs access (add a recipient), or when the cache service lands and a different secret backend is worth its cost.
