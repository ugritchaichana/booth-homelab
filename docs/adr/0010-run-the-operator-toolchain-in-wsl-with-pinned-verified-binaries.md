# 0010. Run the operator toolchain in WSL with pinned, verified binaries

- Status: Accepted
- Date: 2026-10-06
- Deciders: operator
- Decision log: D33 in docs/platform/requirements.md

## Context

The operator needs `tofu`, `sops`, `age`, `ansible`, `xorriso` and `proxmox-auto-install-assistant` on the workstation. Ansible and the installer assistant are Linux-only, and CI runs Linux. An inventory on 2026-10-06 found none of these installed on either the Windows or the WSL side.

Release binaries downloaded at run time are a supply-chain entry point. A checksum file fetched from the same release as the binary detects corruption, not a replaced release. The secrets review of 2026-10-06 flagged exactly this for the first version of the script.

## Options considered

1. Windows-native installs — Windows has no Ansible control node and no assistant package, so a second Linux environment would be needed anyway; two toolchains drift apart.
2. WSL Debian only, binaries fetched with a checksum file from the release — one toolchain, but the checksum has the same origin as the binary.
3. WSL Debian only, binaries pinned by hard-coded sha256 constants, signatures checked once by hand — one toolchain matching Linux CI; each version bump costs one manual verification.

## Decision

Install everything in WSL Debian through one idempotent script, `scripts/bootstrap/operator-toolchain.sh`, run as root.

- Debian archive packages come from apt (`scripts/bootstrap/operator-toolchain.sh:16`).
- `tofu`, `sops` and `gitleaks` are release binaries with the version and sha256 hard-coded as constants (`scripts/bootstrap/operator-toolchain.sh:4-9`); `verify_sha256` aborts before anything is installed (`:51-56`). No checksum file is fetched at run time.
- The `tofu` version equals the IaC CI pin (`.github/workflows/iac-ci.yml:30`) and the `gitleaks` version equals the secret-scan pin (`.github/workflows/secret-scan.yml:22-26`), so the operator and CI run the same tools.
- Before each pin was set, the publisher's checksum file was verified once with `cosign` against its signature bundle. The script does not run `cosign`.
- The Proxmox archive keyring is accepted only when its sha256 equals the value the Proxmox documentation publishes (`:10-12`, `:115-123`); URL: https://pve.proxmox.com/wiki/Package_Repositories.
- The Proxmox repository is pinned at priority 1 (`:130-132`). Per apt_preferences(5) a priority-1 version is installed only when no other version is available, so the repository supplies `proxmox-auto-install-assistant` and cannot replace a Debian package.
- The age private key stays in the Windows profile (`%APPDATA%\sops\age\keys.txt`) per the secret-store decision; WSL reads it through `SOPS_AGE_KEY_FILE` (`scripts/proxmox/build-auto-install-iso.sh:58`).

## Rationale and trade-offs

- Measured 2026-10-06: a copy of the script with one hex digit of the `tofu` pin changed exited 1 with "sha256 mismatch" and installed nothing. A second run on the provisioned distro exited 0 with no download, `Get:` or `sha256 OK` lines.
- `cosign` v3.1.3 was itself trusted only through a same-origin checksum, and is not hash-pinned in any file. Residual risk, accepted for a one-time check.
- The two signature identities differ in strength. OpenTofu's documented identity is scoped to a release branch (`@refs/heads/v1.13`), SOPS's to the exact tag (`@refs/tags/v3.13.3`). Sources: https://github.com/opentofu/opentofu/blob/main/website/docs/intro/install/examples/verify-cosign.sh and https://github.com/getsops/sops/blob/main/.goreleaser.yaml.
- The age key is readable from WSL through `/mnt/c`, and every local administrator account is inside the trust boundary. The upside is that the WSL distro stays disposable.
- Cost: every version bump needs a manual signature check and a new constant. Revisit if bumps become frequent enough to justify verifying signatures in the script.
