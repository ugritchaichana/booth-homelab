# 0022. Render the SSH config with the host key pinned from SOPS

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D50 in docs/platform/requirements.md (refines ADR 0011)

## Context

ADR 0011 reaches the Proxmox VM through the Windows `ssh.exe -W` proxy. The first version set `StrictHostKeyChecking=accept-new` in the inventory and kept the Windows key path in an environment variable. That trusts whatever key answers on the first connection, and `accept-new` stores it unverified. The repository is public, so host keys and fingerprints must not appear in clear text either, and no user-specific path may be committed.

## Options considered

1. `StrictHostKeyChecking=accept-new` or `no` — nothing to maintain, but the first connection is unauthenticated.
2. The host key in clear text in the inventory — verified, but the repository then carries a host fingerprint.
3. The host key SOPS-encrypted per host, and an SSH config rendered outside the repository from the inventory and that secret.

## Decision

Option 3. `scripts/iac/render-ssh-config.sh` writes `~/.config/homelab/ssh_config` and `~/.config/homelab/known_hosts` (mode 600, directory 700) and `scripts/iac/ansible.sh` hands that config to Ansible.

- The public key comes from `iac/secrets/hosts/<name>-ssh.sops.yaml`, key `ssh_host_ed25519_public`. It was captured once over the Windows path, whose own known-hosts file already verified the host, and compared with the fingerprint recorded at install before it was encrypted.
- Each host entry sets `StrictHostKeyChecking yes`, a dedicated `UserKnownHostsFile`, `HostKeyAlias` and `CheckHostIP no`, so the key is matched by host name whether Ansible connects by name or by address.
- The Windows key path is discovered at run time from the Windows profile directory; the key file name comes from `ssh_key_name` in the inventory.
- The proxy hop runs with `BatchMode=yes`, so an unexpected prompt fails instead of hanging.

## Rationale and trade-offs

- Measured 2026-10-07: with the rendered config the connection prints the Proxmox version, and with a deliberately wrong key in a temporary known-hosts file it fails with a host-key error and exit 255.
- The proxy hop to the same address is verified by the Windows known-hosts file, not by the pinned key. The pin protects the inner session, which carries the commands and the API tunnel.
- Encryption hides the key but does not authenticate it, because the recipient is public: the pin rests on git review of the encrypted file, as with any committed configuration.
- Accepted loss: rendering needs the age identity, so the SSH config cannot be produced on a machine without it. A rebuilt host gets a new key and needs its SOPS file re-written; the old pin makes the connection fail closed.
- Revisit if the proxy is dropped for a direct route (ADR 0011): the `ProxyCommand` line is then removed from the renderer.
