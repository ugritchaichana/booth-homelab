# 0023. Run Ansible as a key-only automation user and harden sshd behind a dead-man

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D49 in docs/platform/requirements.md

## Context

Measured on the PVE VM before the first converge (2026-10-06): `sudo` is not installed; sshd has `permitrootlogin yes` and `passwordauthentication yes`; root's `authorized_keys` holds three keys (the workstation key, the WSL automation key and a `root@pve01` RSA key). Ansible would otherwise keep logging in as `root` over a password-capable sshd.

Constraint: a bad sshd or key change over the only access path locks the operator out, and the only recovery is a VM checkpoint (ADR 0019).

## Options considered

1. Keep `root` as the Ansible user, only switch sshd to keys — one account, but every play runs as `root` and the WSL key keeps a root login.
2. A dedicated automation user with key and `NOPASSWD` sudo, sshd hardened in the same run — separates the identity, but a mistake locks the host with no way back.
3. Option 2, with the hardening applied only after a fresh session as the automation user succeeds, and a timed restore armed before the change — the lockout window is bounded.

## Decision

Option 3, implemented by `iac/ansible/roles/base`.

- User `automation`: locked password, key-only, `NOPASSWD` sudo in `/etc/sudoers.d/90-homelab-automation`, validated with `visudo -cf`.
- Root keeps only the workstation key as break-glass, restricted with `from="<management_source>"`. The WSL key is revoked from root by an explicit list; root's key file is not rewritten exclusively, because the `root@pve01` key may be used by the node itself (inferred, not checked).
- sshd drop-in `00-homelab-hardening.conf`: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `AllowTcpForwarding yes` (the root `-W` jump and the automation `-L` API tunnel need it). The drop-in is validated with `sshd -t` before it is written. `PermitOpen` is not used.
- Guard, in order: a fresh non-multiplexed session as `automation` running `sudo -n`; backup of the drop-in and root keys; `systemd-run --on-active=10min --unit=homelab-deadman-ssh` with a restore script; the change and an sshd reload; a second fresh session as `automation`; only then the timer is stopped and the backup removed. The guard runs only when a change is pending, so a repeat run reports `changed=0`.
- One variable, `base_container_test_mode`, skips the guard and the chrony start. Only the Molecule scenario sets it (ADR 0024).

## Rationale and trade-offs

- Measured 2026-10-07 in a disposable Debian 13 instance with systemd, over real SSH (not the PVE VM): first run applied the change and left no dead-man unit; the second run reported `changed=0`. With the automation key unusable, the run stopped at the first fresh-session check with sshd and root keys unchanged and no timer armed. With the second check forced to fail, the timer fired after one minute and restored the previous drop-in state (`passwordauthentication yes`) and root keys.
- Fresh sessions disable SSH multiplexing: a first attempt reused a connection left by the previous run and passed with a key that was no longer valid.
- Accepted loss: `NOPASSWD` sudo makes the automation key root-equivalent, which is inside the isolation boundary of the VM, not a new one.
- Accepted loss: only the root key is source-restricted. The network layer (ADR 0007 and the host firewall that follows) limits who can reach the automation login.
- Not proven: the dead-man on the PVE VM itself, the workstation break-glass login after the change, and writes to root's key file if it is a link into the cluster filesystem (`follow: true` targets the file; its write and mode behaviour there is HYPOTHESIS). The first converge runs behind a checkpoint with the VM stopped (ADR 0019).
- Until the inventory `ansible_user` changes from `root` to `automation`, `site.yml` connects as `root` with a key the run has just revoked; `bootstrap.yml` is the only play meant to connect as `root`.
