# 0033. Keep one SOPS file per consumer and host, with one writer each

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D52 in docs/platform/requirements.md

## Context

Recorded after the implementation, as a late record under the repository's rule that every decision gets an ADR. Implemented by #58 (secret store and root password file), #64 (host key file), #66 (access keys file), #67 (host network file and the API token file's writer), #68 (state passphrase writer in `scripts/iac/tofu.sh`), #73 (root password rotation) and #74 (ciphertexts of the token and the passphrase).

Several tools need secrets from the same repository: the install ISO build, the SSH config renderer, Ansible and OpenTofu. If one file held all of them, every consumer would decrypt every secret, and a second writer could overwrite a value the first one owns. SOPS encrypts a whole file for one recipient (ADR 0009), so the file boundary is the only boundary the store offers.

Under `iac/secrets/` the tree holds six files, read at commit `a9f8b43`:

| Consumer | File | Writer |
|---|---|---|
| `scripts/proxmox/build-auto-install-iso.sh:119` (hashes the root password into the answer file) | `hosts/pve01.sops.yaml` | operator, at install and at rotation |
| `scripts/iac/render-ssh-config.sh:66-67` (pins the host key) | `hosts/pve01-ssh.sops.yaml` | operator, once |
| `iac/inventory/host_vars/pve01.yml:2` (the base role's authorized keys) | `hosts/pve01-access.sops.yaml` | operator |
| `iac/inventory/host_vars/pve01.yml:6-7` (the `pve_firewall` role's host-routed prefixes) | `hosts/pve01-network.sops.yaml` | operator, seeded once from the local Hyper-V override |
| `scripts/iac/tofu.sh:165-166` (API token for the provider) | `tofu/pve01-api.sops.yaml` | the `pve_api_identity` role (`iac/ansible/roles/pve_api_identity/tasks/token.yml`) |
| `scripts/iac/tofu.sh:159` (state and plan encryption key) | `tofu/pve01-state.sops.yaml` | `scripts/iac/tofu.sh <stack> pve01 init-passphrase` |

## Options considered

1. One SOPS file for the whole repository — one place to look, but every consumer decrypts every secret and several writers edit one file.
2. One file per host holding every secret of that host — fewer files, but OpenTofu would still be able to read the root password.
3. One file per consumer and host, one writer per file — more files, and each consumer reads only what it needs.

## Decision

Option 3.

- File names follow `hosts/<host>-<purpose>.sops.yaml` and `tofu/<host>-<purpose>.sops.yaml`. The single rule in `.sops.yaml` matches `^iac/secrets/.*\.sops\.ya?ml$`, so a new file needs no new rule.
- OpenTofu reads only the two files under `tofu/`: `scripts/iac/tofu.sh` runs `sops decrypt --extract` for the one key it needs and exports it inside a subshell. It never opens `hosts/pve01.sops.yaml`, so `root_password` is not in its environment. The tree does not use `sops exec-env`; the separation comes from the file split and from the keys that script extracts.
- Secret values do not go on a command line. The token secret is passed to `sops set --value-stdin` (`token.yml:135-149`, with `no_log`). The passphrase is generated and piped to `sops encrypt --filename-override <target> --input-type json --output-type yaml /dev/stdin` (`scripts/iac/tofu.sh:68`), written to a temporary file in the same directory under `umask 077`, then moved into place. The token id is not secret and is set with an argument (`token.yml:151-159`).
- The `/dev/shm` plaintext fallback is not implemented. The only `/dev/shm` use is `scripts/proxmox/build-auto-install-iso.sh:85`, which reads a secret to build the ISO and does not write a SOPS file.
- Host-routed prefixes are not secret, but they stay out of git in plaintext. They live in `hosts/pve01-network.sops.yaml`, and Ansible reads them with the `community.sops.sops` lookup (`iac/inventory/host_vars/pve01.yml:6`).

## Rationale and trade-offs

- A leak or a bug in one consumer exposes only the file that consumer reads, and a failed write can only damage the file of its own writer.
- The `sops set --value-stdin` path was measured on 2026-10-07 in a scratch directory with a throwaway age key (ADR 0026, Rationale): it needs an existing file and a JSON-encoded value. sops issue 1932 reports that `--value-stdin` does not work as documented; `scripts/bootstrap/operator-toolchain.sh` only checks the pinned version and does not repeat that measurement, so a sops upgrade is not covered by a check in this tree.
- Accepted loss: "one writer per file" is a convention stated in `iac/secrets/README.md`, not something SOPS or the repository enforces. The operator-written files have no script as a writer, so nothing stops a second hand edit.
- Accepted loss: more files mean more places to rotate. After a leak of the age identity every file must get new values, not only a new recipient (`iac/secrets/README.md`).
