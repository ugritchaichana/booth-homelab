# 0042. Install runner template toolchains from release tarballs with pinned hashes

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D69 in docs/platform/requirements.md

## Context

The self-hosted path of the CI workflow never runs `setup-dotnet` or `setup-node`: those steps only run on the hosted fallback (`.github/workflows/reusable-sdet-pipeline.yml:102-106,153-157` and the angular job's fallback step). A runner clone must therefore already carry .NET SDK 8.0, Node 22 and the tools the workflow scripts call (`git`, `curl`, `jq`, `tar`, `zstd`, `zip`, `unzip`, `file`, `diff`).

A template is cloned into every runner, so a poisoned or silently changed toolchain reaches every CI job and the cache writer keys on master pushes. The security review of the template builder ranks provenance as a build-failing rule, not advice.

## Options considered

1. Third-party apt repositories (Microsoft, NodeSource) — upgrades come through apt, but each repository adds a signing key that can sign a replacement for any Debian package unless scoped.
2. Official release tarballs with a pinned hash per artifact — no third-party key, every change is a reviewed edit of one file.
3. Installer scripts piped to a shell — fastest to write, no integrity check, rejected.

## Decision

Use option 2 for all four artifacts, listed in `iac/ansible/roles/pve_templates/files/bundles/lxc-runner/versions.yml`.

- .NET SDK 8.0 and 10.0 side by side in one root (sha512 from the official release metadata). .NET 8 ends support on 2026-11-10; the date is recorded in the versions file and in every manifest.
- Node 22 LTS (sha256 from `SHASUMS256.txt`; the operator verifies its signature when pinning, never on the host).
- `actions/runner` (sha256 from the release notes) under `/opt/actions-runner`, owned by a non-root `runner` user with a locked password and no sudo. It is installed and never configured: no `.runner`, no `.credentials*`. The build fails if any exists.
- Operating-system dependencies of the runner and the base tools are installed by Debian package name, never by piping `installdependencies.sh` to a shell. Debian packages follow the Debian security cadence and are not version-pinned; the manifest records every installed version.
- The in-guest run asserts installed versions equal `versions.yml` and fails the build otherwise. The manifest records OS release, kernel, each toolchain version, the runner version and the sha256 of `versions.yml`.
- `tests/isolation/lib/lint-template-content.py` runs over every `files/bundles/*/` and fails on an artifact without an exact version and hash, a pipe to a shell, `[trusted=yes]`, `--allow-unauthenticated`, the word `latest`, and an apt source without `signed-by=` and a pinned key fingerprint.

## Rationale and trade-offs

- The measured fact behind the choice: the pinned tarball hashes were checked against downloaded files, and the Node and runner archives ship an empty `.npmrc` and a help text that contains a placeholder private key. The build's own scan forbids both, so the playbook removes the empty file and the npm docs, and `scan-allowlist.txt` lists the three remaining config-definition files by sha256 and path.
- Named gaps, deliberately not in the template: the MinIO client `mc` (the cache decision belongs to Phase 4), PowerShell (`pwsh`), the GitHub CLI and Docker (hosted-only workflows and the Docker class template).
- A manifest is reported by the guest: it catches drift and our own mistakes, not a signed but malicious upstream.
- Every version bump is a manual edit; nothing detects new upstream releases. A bump of Node or the runner can change the allowlist entries, and the build fails closed with the path and hash to review.
- Debian trixie is the base; hosted-runner parity is at distribution level only.
