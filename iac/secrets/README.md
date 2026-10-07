# Secrets

Files here are encrypted with [sops](https://github.com/getsops/sops) for one age recipient, selected by the rule in the repository-root `.sops.yaml` (`^iac/secrets/.*\.sops\.ya?ml$`).

Recipient (public): `age1n0vn2cctfh4acum3pygfgc2qn5889es6pnllc6q9m0a52e6gc90q7mr2sc`

| File | Holds | Writer |
|---|---|---|
| `hosts/pve01.sops.yaml` | `root_password` of the `pve01` host (hashed into the install answer file at build time) | operator, at install |
| `hosts/pve01-ssh.sops.yaml` | `ssh_host_ed25519_public`, the host key that `scripts/iac/render-ssh-config.sh` pins in the rendered `known_hosts` | operator, captured once over an already-trusted path |
| `hosts/pve01-access.sops.yaml` | `root_authorized_keys`, `root_authorized_keys_revoked`, `automation_authorized_keys`: operator public keys for the base role, read by `iac/inventory/host_vars/pve01.yml` | operator |
| `hosts/pve01-network.sops.yaml` | `host_routed_prefixes`: prefixes the workstation routes elsewhere, denied to guests by the `pve_firewall` role | operator, seeded once from the local Hyper-V override |
| `hosts/pve01-cache.sops.yaml` | `writer_password` (and the non-secret `writer_user`): the one credential that may write to the build cache, read by `iac/inventory/group_vars/cache.yml` | `scripts/iac/cache-writer-secret.sh` |
| `hosts/cache01-ssh.sops.yaml` | `ssh_host_ed25519_public` of the cache container, pinned by `scripts/iac/render-ssh-config.sh` when the file exists | operator, captured through `pct exec` on the Proxmox host after the first apply |
| `tofu/pve01-api.sops.yaml` | `token_id`, `token_secret` of the OpenTofu API token | the `pve_api_identity` role |
| `tofu/pve01-state.sops.yaml` | `state_passphrase`: 48 random bytes, base64, the key material for OpenTofu state and plan encryption | `scripts/iac/tofu.sh <stack> pve01 init-passphrase` |

Each file has one writer. A host named `<name>` in `iac/inventory/hosts.yml` needs `hosts/<name>-ssh.sops.yaml` before the SSH config can be rendered.

## Use

The private identity is not in this repository. Point sops at it with `SOPS_AGE_KEY_FILE`, or place it at the sops default (`~/.config/sops/age/keys.txt`, `%APPDATA%\sops\age\keys.txt` on Windows).

```sh
sops -d --extract '["root_password"]' iac/secrets/hosts/pve01.sops.yaml   # read one value
sops iac/secrets/hosts/pve01.sops.yaml                                      # edit in place
```

A new secret file must match the path rule above, otherwise sops refuses to encrypt it. Run sops from the repository root so the rule resolves.

## Recovery and rotation

- There is a single recipient. If the owner's offline copy of the age identity is lost, every secret here is unrecoverable; keep that copy outside this machine.
- If the identity leaks, change every secret value, not only the encryption: old commits stay decryptable forever, so re-encrypting the same value to a new recipient is not a rotation. Generate new values, encrypt to a new recipient, commit, apply to the hosts.
- Never commit decrypted output or an age identity. gitleaks flags both, and the CI secret scan runs gitleaks.
