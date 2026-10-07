# P2-J1 report: pve01 repositories and upgrade baseline

Branch `infra/pve-baseline-repos`, worktree `<user-home>/Desktop/Project/_wt-pve-baseline` (stacked on PR #58 head c0e7e47). Nothing committed or pushed.

## Files (all untracked, new)
- `iac/ansible/inventory/pve01.yml`
- `iac/ansible/playbooks/pve-baseline.yml`
- `iac/ansible/roles/pve_repos/defaults/main.yml`
- `iac/ansible/roles/pve_repos/tasks/main.yml`
- `ansible.cfg` NOT touched.

## Versions
| | before | after |
|---|---|---|
| proxmox-ve | 9.1.0 | 9.2.0 |
| pve-manager | 9.1.1 | 9.2.21 |
| running kernel | 6.17.2-1-pve | 7.0.14-20-pve |
| installed kernels | 6.17.2-1 | 6.17.2-1, 6.17.13-21, 7.0.14-20 |

The no-subscription repo carries PVE 9.2 and `proxmox-default-kernel` 2.1.0 pulls the 7.0 kernel, so the host ended up on 7.0, not 6.17. The pinned wording "PVE 9.1.1 / kernel 6.17.2" elsewhere is now stale. Hyper-V checkpoint `post-install` still restores the old state.

## Design
- `ansible.builtin.deb822_repository` with names `pve-enterprise` and `ceph` overwrite the installer's `.sources` files in place (`Enabled: no`). `pve-no-subscription` is added with the stanza from the Proxmox wiki "Package Repositories" (No-Subscription section): URIs `http://download.proxmox.com/debian/pve`, Suites `trixie`, Components `pve-no-subscription`, Signed-By `/usr/share/keyrings/proxmox-archive-keyring.gpg`. Fetched and read on 2026-10-06.
- `apt` with `update_cache` + `upgrade: full` (dist-upgrade), `DEBIAN_FRONTEND=noninteractive`, `async: 1800 poll: 15`.
- Reboot only when `/var/run/reboot-required` exists or the newest `/boot/vmlinuz-*` (sort -V) differs from `ansible_facts.kernel`; `ansible.builtin.reboot`, timeout 900, test_command `pveversion`.
- Inventory: ProxyCommand through the Windows `ssh.exe`; the Windows key path comes from env `PVE01_WIN_SSH_KEY` via host var `pve_win_ssh_key` (unset -> fails naming the variable, measured; `grep -il <deny-list-patterns>` over the new files returns nothing). `ansible_become: false`, pipelining on, `ServerAliveInterval=15`.
- The playbook references the role as `{{ playbook_dir }}/../roles/pve_repos` with `# noqa role-name[path]`, so it works from any cwd with no `ansible.cfg` (ansible-lint production profile passes).

## How to run (the lead)
WSL distro `Debian`, from the worktree root as cwd, env `PVE01_WIN_SSH_KEY=<user-home>/.ssh/homelab_pve01_ed25519`, `mkdir -p ~/.ansible`:
`ansible-playbook -i iac/ansible/inventory/pve01.yml iac/ansible/playbooks/pve-baseline.yml`
No `ANSIBLE_CONFIG` needed. Do NOT set it to `iac/ansible/ansible.cfg` for this playbook: its `ssh_args` (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`) come first and would override the pinned-key intent of the inventory.

## Runs
- run 1a (`p2j1-run1a-hung.txt`): repos changed 3x, `apt dist-upgrade` finished on PVE (apt history End-Date 16:58:53, 214 packages), but the Ansible task never returned; ~10 min later I killed it (`apt-get -s dist-upgrade` = 0 and `dpkg --audit` clean at that point). Cause is UNKNOWN (HYPOTHESIS: the single long-held session stalled through the proxy hop, or the in-flight openssh/libc/python upgrade). Measured afterwards (`p2j1-idle-test.txt`): a 420 s silent `command` task through the new inventory (ServerAliveInterval=15, no async) returned exit 0, so idle length alone does not reproduce the hang. The async/poll mitigation has NOT been exercised against a long upgrade; a genuine pristine run needs the lead to restore Hyper-V checkpoint `post-install` and run once (full 214-package upgrade + reboot).
- run 1b (`p2j1-run1.txt`): `ok=8 changed=1` (only the reboot), exit 0. The repo tasks were already `ok` from 1a, so the true first-ever apply is split across 1a (changed=3 repos + upgrade, no recap because killed) and 1b (reboot).
- run 2 (`p2j1-run2.txt`): `pve01 : ok=7 changed=0 unreachable=0 failed=0 skipped=1`, exit 0.
- Repo-level idempotency (3 deb822 tasks `ok` on 1b, `update_cache` = ok) is measured; first-run changed count for a pristine host is 5 (3 repos + upgrade + reboot) by task, not by one recap.

## DoD lines (verbatim, `p2j1-postcheck.txt`)
- `--- pending` -> `0`
- `apt-get update` error/warn line count -> `0`; tail `Hit:4 http://download.proxmox.com/debian/pve trixie InRelease`
- `/etc/apt/sources.list.d/ceph.sources:Enabled: no`, `pve-enterprise.sources:Enabled: no`, `pve-no-subscription.sources:Enabled: yes`
- `pveversion -v | head -5`: `proxmox-ve: 9.2.0 (running kernel: 7.0.14-20-pve)` / `pve-manager: 9.2.21 (running version: 9.2.21/4f6e0ac86f9e8c7f)` / `proxmox-kernel-helper: 9.2.0` / `proxmox-kernel-7.0: 7.0.14-20` / `proxmox-kernel-7.0.14-20-pve-signed: 7.0.14-20`
- `uname -r`: `7.0.14-20-pve`
- nested smoke on the new kernel: `egrep -c "vmx|svm" /proc/cpuinfo` -> `12` (I ran `grep -Ec`), `crw-rw---- 1 root kvm 10, 232 Oct  6 17:08 /dev/kvm`, `/sys/module/kvm_amd/parameters/nested` -> `1`. PASS.
- `systemctl is-system-running` -> `running`, no failed units.

## Checks
- `ansible-playbook --syntax-check` new playbook: exit 0.
- `ansible-lint --nocolor` (apt-installed 25.6.1+really25.2.1 in WSL, trixie) on the playbook, role and inventory: `Passed: 0 failure(s), 0 warning(s) on 5 files ... profile 'production'`.
- Existing CI syntax checks (`iac-ci.yml`, four old playbooks, `hosts.ini.example`): exit 0 each when `ANSIBLE_CONFIG=iac/ansible/ansible.cfg` (as CI loads it). Without it they fail (measured warning: `Ansible is being run in a world writable directory (...), ignoring it as an ansible.cfg source`, WSL /mnt/c) on role resolution, unrelated to this change.

## Gaps for the lead
- `iac-ci.yml` does not syntax-check `pve-baseline.yml`; adding it needs `-i inventory/pve01.yml` (env var lookup is lazy, syntax-check passes without it). Outside my write set.
- Task names in output show the full role path (cosmetic, from the path-style role reference); run logs therefore contain the local worktree path.
- Mux host-key pinning: inner hop uses `accept-new` with `~/.ansible/pve01_known_hosts`; stored fingerprint verified `SHA256:F8rbz3+QW0C4VMKImBoY+jZ8FqVoA1JsjM3ZKPfKitY` (matches). The outer Windows hop uses Windows known_hosts.
- Reboot condition is "newest `/boot/vmlinuz-*` by sort -V != running kernel". Today they match (7.0.14-20-pve). If a kernel is pinned or a newer kernel is not the default boot entry, the condition stays true and every run reboots (breaks idempotency).
- Run 2 was re-run after the final inventory edit (host var for the key path): `ok=7 changed=0`, exit 0. Run 1b used the earlier equivalent inventory.
- Ceph no-subscription repo not added (not asked). Subscription nag untouched.
