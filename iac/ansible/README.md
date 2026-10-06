# Ansible

Host configuration for the lab. Host data comes from `../inventory/` (ADR 0021); the SSH control path comes from `scripts/iac/ansible.sh` (ADR 0022).

| Path | Purpose |
| :--- | :--- |
| `ansible.cfg` | Inventory, roles path and mandatory host-key checking. |
| `requirements.yml` | Pinned collections. |
| `requirements-ci.txt` | Hash-locked Python toolchain for CI and local linting. |
| `playbooks/bootstrap.yml` | First contact as `root`: creates the automation user. |
| `playbooks/site.yml` | Steady state, run as the automation user. |
| `roles/base/` | Provider-neutral Debian baseline. |

## Toolchain

```sh
python3 -m venv ~/.venvs/homelab-ansible
~/.venvs/homelab-ansible/bin/pip install --require-hashes -r iac/ansible/requirements-ci.txt
ansible-galaxy collection install -r iac/ansible/requirements.yml
```

Static checks, from the repository root:

```sh
ansible-lint --profile production iac/ansible
ANSIBLE_CONFIG=iac/ansible/ansible.cfg ansible-playbook --syntax-check iac/ansible/playbooks/site.yml
```

Role test (needs a Docker daemon, so it runs in CI): `cd iac/ansible/roles/base && molecule test`.

## Applying to a host

```sh
bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root
bash scripts/iac/ansible.sh site.yml
```

The inventory `ansible_user` is `automation`; `bootstrap.yml` is the only play that connects as `root`, hence its `-e ansible_user=root`. Host keys come from `iac/inventory/host_vars/<host>.yml`, which reads them from `iac/secrets/hosts/<host>-access.sops.yaml`.

## Role `base`

Order inside the role: automation user and sudo, time sync, journal cap, then SSH hardening.

| Area | Behaviour |
| :--- | :--- |
| Automation user | Key-only, locked password, `NOPASSWD` sudo through a drop-in validated by `visudo -cf`. Keys come from `base_automation_authorized_keys`. |
| Root keys | Keys in `base_root_authorized_keys` get `from="<management_source>"`; keys in `base_root_authorized_keys_revoked` are removed. Other root keys are left alone. |
| sshd | Drop-in `00-homelab-hardening.conf` (sorts first, so it wins over later drop-ins), validated with `sshd -t`. |
| Time sync | chrony with the servers from `time_servers`, written to `/etc/chrony/sources.d/`. |
| Journal | `SystemMaxUse` from `journald_system_max_use`. |

Role inputs are the `base_*` variables in `roles/base/defaults/main.yml`; the inventory names `automation_user`, `management_source`, `time_servers`, `journald_system_max_use` and `deadman_minutes` feed them. The key lists have no default on purpose: the role fails its assertions before changing anything while a list is empty.

### SSH change guard

Before anything else the role refuses to run while a `homelab-deadman-ssh` timer is armed, or while an `armed` marker exists without a timer (inspect the host and `journalctl -t homelab-deadman`, then delete the marker). `site.yml` also refuses to run unless the connection user is the automation user.

When the sshd drop-in or the root keys would change, the role does this in order:

1. Open a fresh session as the automation user (no multiplexing, the wrapper's ssh arguments kept) and run `sudo -n`; stop if it fails.
2. Back up the current drop-in and root keys, write an `armed` marker, then arm `systemd-run --on-active=<deadman_minutes>min --unit=homelab-deadman-ssh` with a script that restores them. The enabled unit `homelab-deadman-ssh-boot` runs the same script at boot while `armed` exists, so a reboot inside the window does not disarm the restore.
3. Edit the root keys (on PVE the key file is a link into the cluster filesystem, so the file it points to is edited in place) and install the drop-in; check it with `sshd -t`, then reload sshd.
4. Assert that each kept root key occurs once with its `from=` option and each revoked key nowhere. After the reload, open another fresh session as the automation user and assert the effective `sshd -T` values, that the timer is still active and that no `fired` marker exists; only then delete the `armed` marker, stop the timer and delete the state.

If a step after the arming fails, the timer stays armed and restores the previous access. Nothing is armed when nothing changes, so a second run reports `changed=0`.

### Test mode

`base_container_test_mode: true` skips the fresh-session checks, the dead-man and the chrony start and restart, because a container has no second SSH login, no host clock and no timer to lock out. Only the Molecule scenario sets it. The role asserts the value is a boolean and is `true` only on a container connection, so a real host cannot run with it on.

### Line endings

`iac/ansible/.gitattributes` forces LF: a CRLF template would put a carriage return into the sshd drop-in and the restore script.
