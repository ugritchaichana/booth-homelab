# 0023. Run Ansible as a key-only automation user and harden sshd behind a dead-man

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D49 in docs/platform/requirements.md

## Context

Measured on the PVE VM before the first converge (2026-10-06): `sudo` is not installed; sshd has `permitrootlogin yes` and `passwordauthentication yes`; root's `authorized_keys` holds three keys (the workstation key, the WSL automation key and a `root@pve01` RSA key). Measured read-only on the same VM 2026-10-07: `/root/.ssh/authorized_keys` is a symbolic link to `/etc/pve/priv/authorized_keys`, a `root:www-data` mode 600 file on the cluster filesystem. Ansible would otherwise keep logging in as `root` over a password-capable sshd.

Constraint: a bad sshd or key change over the only access path locks the operator out. Recovery is a VM checkpoint (ADR 0019) or the Hyper-V console with the root password set by the answer file (console path untested).

## Options considered

1. Keep `root` as the Ansible user, only switch sshd to keys — one account, but every play runs as `root` and the WSL key keeps a root login.
2. A dedicated automation user with key and `NOPASSWD` sudo, sshd hardened in the same run — separates the identity, but a mistake locks the host with no way back.
3. Option 2, with the hardening applied only after a fresh session as the automation user succeeds, and a timed restore armed before the change — the lockout window is bounded.

## Decision

Option 3, implemented by `iac/ansible/roles/base`.

- User `automation`: locked password, key-only, `NOPASSWD` sudo in `/etc/sudoers.d/90-homelab-automation`, validated with `visudo -cf`.
- Root keeps only the workstation key as break-glass, restricted with `from="<management_source>"`. The WSL key is revoked from root by an explicit list. Keys are edited with `lineinfile` on the file the path resolves to, with no owner, group or mode, because the cluster filesystem refuses ownership changes and `authorized_key` would raise after writing. The file is not rewritten exclusively, because PVE re-adds its own `root@pve01` key at each `pveproxy` start (pve-cluster `Setup.pm`, `pveproxy.service`).
- sshd drop-in `00-homelab-hardening.conf`: `PermitRootLogin prohibit-password`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `AllowTcpForwarding yes` (the root `-W` jump and the automation `-L` API tunnel need it). The drop-in is checked standalone with `sshd -t -f` before it is written and merged with `sshd -t` before the reload. `PermitOpen` is not used.
- Guard, in order: a fresh session as `automation` running `sudo -n`; backup of the drop-in and root keys; an `armed` marker and `systemd-run --on-active=10min --unit=homelab-deadman-ssh` with a restore script; the change and an sshd reload; a second fresh session as `automation`; an assertion that `sshd -T` shows the hardened values, that the timer is still active and that no `fired` marker exists; only then the timer is stopped and the state removed. The guard runs only when a change is pending, so a repeat run reports `changed=0`.
- Fresh sessions add `-o ControlPath=none` through `ansible_ssh_extra_args`, so they neither reuse a multiplexed connection nor drop the `ANSIBLE_SSH_ARGS` of the wrapper (`-F` ssh config, host-key checking).
- A persistent `homelab-deadman-ssh-boot.service`, enabled by the role, runs the same restore script at boot while the `armed` marker exists, so a reboot inside the window does not disarm the restore. A restore that succeeds removes `armed` and leaves `fired`.
- The role refuses to start while a `homelab-deadman-ssh` timer is armed, and `site.yml` refuses to run unless it is connected as the automation user.
- Stale state is refused, not trusted: the role stops at its start when an `armed` marker exists without an active timer (a boot would roll back a good configuration), and the success path deletes `armed` before it stops the timer. After the key edits it asserts, on the key blob rather than the whole line, that each kept key occurs exactly once with its `from=` option and each revoked key occurs nowhere, because `lineinfile` replaces only the last match and does not match options that contain a space. The boot unit is also ordered after `pveproxy.service`, which rewrites root's key file at start on PVE.
- One variable, `base_container_test_mode`, skips the guard and the chrony start. The role asserts it is a real boolean and that it is `true` only on a container connection (`community.docker.docker`, `docker`), so a mistyped `-e` value or an SSH run cannot turn it on. Only the Molecule scenario sets it (ADR 0024).

## Rationale and trade-offs

- Measured 2026-10-07 in a disposable Debian 13 instance with systemd, over SSH to its own loopback (not the PVE VM, and not through the `-W` jump): first run applied the change and left no dead-man unit; the second run reported `changed=0`. With the automation key unusable, the run stopped at the first fresh-session check with sshd and root keys unchanged and no timer armed. With the post-check forced to fail, the timer fired and restored the previous drop-in state and root keys; the same failure followed by a restart of the instance restored them at boot from the persistent unit. A drop-in overridden by an earlier `PermitRootLogin yes`, and a timer that fired before the cancel, each failed the run at the new assertions.
- Measured in the same instance: with the wrapper's `ANSIBLE_SSH_ARGS`, a task-level `ansible_ssh_args` dropped `-F`; `ansible_ssh_extra_args` kept it, with exactly one `ControlPath=none`. Before the fix, a fresh-session check reused a connection left by the previous run and passed with a key that was no longer valid.
- Measured with a stand-in for the cluster filesystem (a FAT loop mount that refuses chown to root:root and accepts `root:www-data`): the previous `authorized_key` code failed with `Operation not permitted` after writing; the `lineinfile` code left the link in place, changed one line to carry `from=`, removed the revoked key and a repeat run reported `changed=0`. The real cluster filesystem was not touched, so its rename and write behaviour for this file stays unproven.
- Accepted loss: `NOPASSWD` sudo makes the automation key root-equivalent, which is inside the isolation boundary of the VM, not a new one.
- Accepted loss: only the root key is source-restricted. The network layer (ADR 0007 and the host firewall that follows) limits who can reach the automation login. Every automation login also arrives through the root `-W` jump, so a bad root-key change takes both logins down; the dead-man is what covers that.
- Not proven: the guard on the PVE VM itself and the workstation break-glass login after the change. The first converge runs behind a checkpoint with the VM stopped (ADR 0019).
