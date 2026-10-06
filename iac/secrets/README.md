# Secrets

Files here are encrypted with [sops](https://github.com/getsops/sops) for one age recipient, selected by the rule in the repository-root `.sops.yaml` (`^iac/secrets/.*\.sops\.ya?ml$`).

Recipient (public): `age1n0vn2cctfh4acum3pygfgc2qn5889es6pnllc6q9m0a52e6gc90q7mr2sc`

| File | Holds |
|---|---|
| `hosts/pve01.sops.yaml` | `root_password` of the `pve01` host (hashed into the install answer file at build time) |

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
