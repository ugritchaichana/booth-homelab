# Ansible

Host configuration for the lab. Host data comes from `../inventory/` (ADR 0021); the SSH control path comes from `scripts/iac/ansible.sh` (ADR 0022).

| Path | Purpose |
| :--- | :--- |
| `ansible.cfg` | Inventory, roles path and mandatory host-key checking. |
| `requirements.yml` | Pinned collections. |
| `requirements-ci.txt` | Hash-locked Python toolchain for CI and local linting. |
| `playbooks/bootstrap.yml` | First contact as `root`: switches the Proxmox repositories, then creates the automation user. |
| `playbooks/site.yml` | Steady state, run as the automation user. On every host: `base`. On the Proxmox hosts, in order: `hyperv_guest`, `pve_host`, `hyperv_guest` again (after a possible reboot), `pve_api_identity`, `pve_firewall`, `pve_templates`. |
| `playbooks/cache.yml` | Build cache service. Play 1 reads back the cache container's firewall and starts the container only if it complies; play 2 installs python3; play 3 applies `cache_service`. Run with `-i iac/inventory/hosts.yml -i iac/inventory/cache.yml`; `site.yml` never touches it. |
| `playbooks/r15-verify.yml` | R15 proof, run on demand: creates the probe control key (tag `r15_keygen`), starts the probe guests, runs `tests/isolation/r15-probe.sh` in each (and in the cache container) over the control channel, checks the guests' firewall options for drift, fetches the output (ADR 0031, 0032). |

## Roles

| Role | Purpose | Decision |
| :--- | :--- | :--- |
| `base/` | Provider-neutral Debian baseline: automation user, sudo, time sync, journal cap, sshd hardening behind a dead-man. | ADR 0023 |
| `hyperv_guest/` | Blocks `hv_sock` and asserts no KVP, VSS or file-copy daemon. | ADR 0028 |
| `pve_host/` | Proxmox repositories (`pve-no-subscription`), full upgrade, reboot on a new kernel, nested-KVM assert. | ADR 0005 |
| `pve_api_identity/` | OpenTofu's API user `tofu@pve`, seven purpose roles, the pools `homelab` and `templates`, ACLs and the privilege-separated token. | ADR 0026, 0036 |
| `pve_firewall/` | `cluster.fw`, `host.fw`, the `guest-egress` and `cache-ingress` security groups, the firewall dead-man and the guest firewall guard timer. | ADR 0025, 0027, 0037, 0047 |
| `pve_templates/` | Golden template framework: the `homelab-template` root orchestrator (`build`, `rollback`, `status`, `repair`), the non-root sandboxed guest-facing step, the in-guest `finalize.sh`, class bundles `lxc-runner` and `vm-docker`, base images pinned by sha512, `snippets` content, the weekly rebuild timer. | ADR 0038 to 0043; `RUNBOOK.md` section 9 |
| `cache_service/` | `bazel-remote` pinned by version and sha256 in the cache container, service user, htpasswd with one writer, the address wait and CAS sweep before each start, a hardened systemd unit. | ADR 0048, 0050; `RUNBOOK.md` section 12 |

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
for t in tests/isolation/test-*.sh; do bash "$t"; done
```

Role test (needs a Docker daemon, so it runs in CI): `cd iac/ansible/roles/base && molecule test`.

## Applying to a host

```sh
bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root
bash scripts/iac/ansible.sh site.yml
bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml
```

The inventory `ansible_user` is `automation`; `bootstrap.yml` is the only play that connects as `root`, hence its `-e ansible_user=root`. Host keys come from `iac/inventory/host_vars/<host>.yml`, which reads them from `iac/secrets/hosts/<host>-access.sops.yaml`. A second run of `site.yml` must report `changed=0`, unless the host applied upstream package updates in between: the `pve_host` role upgrades and reboots into a newer kernel, so drain any pool first once runners exist.

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

## Roles for Proxmox hosts

- `pve_host`: `tasks/repos.yml` disables the enterprise repositories and enables `pve-no-subscription` as deb822 sources (it works before `sudo` exists, so `bootstrap.yml` runs it first); the rest of the role upgrades, reboots into a newer kernel and asserts nested KVM.
- `pve_api_identity`: creates `tofu@pve` without a password, the pools and the privilege-separated token. One role per purpose, each granted only on its path (`defaults/main.yml`): `HomelabGuests` on pool `homelab`; `HomelabTemplateClone` (`VM.Clone`, `VM.Audit`) on pool `templates` and nowhere else; `HomelabDisks` on the guest-disk storage; `HomelabTemplates` on the image storage; `HomelabNodeDownload` on the node; `HomelabGuestNetwork` on each guest vnet path; `HomelabNetworkAdmin` on `/sdn`; `NoAccess` on `/sdn/zones/localnetwork`. The role asserts that `Permissions.Modify`, `Sys.Modify` and `User.Modify` are in none of them. The token secret goes to `iac/secrets/tofu/<host>-api.sops.yaml` through `sops set --value-stdin`; nothing is printed or placed on a command line. A run skips an existing token; `-e pve_api_identity_rotate=true` replaces it. The sops key must be readable by the controller.
- `pve_firewall`: writes `/etc/pve/firewall/cluster.fw` and `/etc/pve/nodes/<node>/host.fw` behind a dead-man that restores the previous files, also at boot. Host-routed prefixes come from `iac/secrets/hosts/<host>-network.sops.yaml`. A root-owned timer (`homelab-guest-firewall-guard`) stops any guest whose firewall settings differ from the per-vnet policy in `/etc/homelab/guest-firewall-guard-policy.json`, including a guest with a NIC on any other bridge; the role also turns off IPv6 router advertisements for the host. `bash tests/isolation/test-cluster-fw-render.sh` and `test-guest-fw-guard.sh` check the rendered rules and the guard offline.
- `pve_templates`: see `RUNBOOK.md` section 9 for building, rolling back, bumping a pinned toolchain and recovering a failed build. `bash tests/isolation/test-template-build.sh` and the other `test-template-*.sh` files check the logic against fakes.
- `cache_service`: see `RUNBOOK.md` section 12. `bash tests/isolation/test-cache-service-role.sh` checks the rendered unit and the role's pins.
