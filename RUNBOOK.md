# Runbook

How to build the platform from zero and operate it day to day. Every step names who performs it and the exact command.

| Role | Meaning |
|---|---|
| owner | The person who accepts the Windows elevation prompt and holds the GitHub repository settings. |
| operator (Windows) | The same person's non-elevated Windows prompt (`cmd.exe`). |
| operator (WSL) | The WSL Debian shell, at the repository root. |
| root on pve01 | A shell on the Proxmox VE VM with `sudo`, reached from WSL as `$pve sudo ...`. |
| CI | A GitHub Actions workflow in this repository. |

Convention for every WSL step that reaches the host:

```sh
pve="ssh -F ~/.config/homelab/ssh_config pve01"
```

The host account is the key-only automation user, which uses `sudo` for root (ADR 0023). The API token cannot delete or retag a template; root is the only identity that builds, promotes and rolls back templates (ADR 0036, ADR 0040).

## Contents

1. What this runbook covers
2. Build from zero
3. Day-2 operations
4. Verification and evidence
5. Troubleshooting
6. Retired

## 1. What this runbook covers

Covered (Phases 1 to 4 of `docs/platform/requirements.md`, all with their DONE WHEN met):

- a Proxmox VE 9 VM inside Hyper-V on the Windows workstation, installed unattended, behind an internal switch, NAT and host-side port ACLs (ADR 0003, 0004, 0006, 0007);
- the host baseline: key-only SSH, repositories, upgrade, firewall, API identity, OpenTofu state, guest network (ADR 0012, 0023, 0025 to 0030);
- golden templates `lxc-runner` and `vm-docker` (ADR 0038 to 0044);
- the build cache service `build-cache-debian-13` (SSH alias `build-cache`) and its client wiring (ADR 0045 to 0051);
- guests sized by a cloud flavor, created by one command (ADR 0055).

Not covered: Phases 5 to 8 are not built (runner pool controller, reusable workflows and cutover, observability and resilience, runbook timed rebuild and portability). The self-hosted CI path cannot run until the Phase 5 runners exist; hosted runners carry CI today (row 68, hosted run with the cache disabled). What is open, what the next phase needs first and the entry gates are in `docs/handoff/README.md`.

Where to look first:

| Question | File |
|---|---|
| Why a choice was made | `docs/adr/` (index in `docs/adr/README.md`) |
| What was required and measured | `docs/platform/requirements.md` (the row numbers below are its rows) |
| What broke on the real host | `docs/knowledge/real-host-defects.md` |
| Which test proves what, and the command | `docs/knowledge/test-catalogue.md`; coverage numbers in `docs/knowledge/coverage.md` |
| Worked examples with real output | `docs/handoff/examples.md` |
| Run transcripts | `docs/evidence/<phase>/INDEX.md` |
| Hyper-V scripts in depth | `scripts/hyperv/README.md` |
| Secrets files and their writers | `iac/secrets/README.md` |

## 2. Build from zero

### 2.1 Workstation prerequisites

1. Windows 11 Pro (or Server 2022+) with virtualization on in firmware and a WSL Debian 13 distribution. Role: owner. The WSL install itself has no script here.

   ```bat
   wsl.exe -l -v
   ```

   Expected: the distribution is listed.

2. Install the pinned operator toolchain (apt packages, `tofu`, `sops`, `gitleaks`, `tflint`, `ansible-lint`, the Proxmox repository keyring, `proxmox-auto-install-assistant`). Checksums are constants in the script and a mismatch installs nothing (ADR 0010). Role: operator (WSL), as root.

   ```sh
   sudo bash scripts/bootstrap/operator-toolchain.sh
   ```

   Expected: a second run installs nothing and prints the version table.

3. Ansible Python toolchain and collections. Role: operator (WSL). Put `~/.venvs/homelab-ansible/bin` first on `PATH`.

   ```sh
   python3 -m venv ~/.venvs/homelab-ansible
   ~/.venvs/homelab-ansible/bin/pip install --require-hashes -r iac/ansible/requirements-ci.txt
   ansible-galaxy collection install -r iac/ansible/requirements.yml
   ```

4. Create the age identity once, in the Windows profile; it is never printed or committed (ADR 0009). Keep an off-machine copy: without it every secret is unrecoverable. Role: operator (WSL). This is the standard age command, not a repo script; run it only when the file does not exist. The repo scripts find the path by themselves; `build-auto-install-iso.sh` needs `export SOPS_AGE_KEY_FILE=<that path>`.

   ```sh
   age-keygen -o "<WSL form of %APPDATA%>/sops/age/keys.txt"
   ```

5. Use the repository's existing identity by restoring the offline copy to the same path. For a fork or a new identity, put the new public key into `.sops.yaml`, delete the encrypted files under `iac/secrets/` and recreate each one by its writer (step 7). Role: owner. See `iac/secrets/README.md`, "Recovery and rotation".

6. Two ed25519 key pairs with the same file name `homelab_pve01_ed25519` (`ssh_key_name` in `iac/inventory/hosts.yml`). The Windows one is the root break-glass key and the proxy-hop key (ADR 0011); the WSL one is the automation key. Role: operator. Standard OpenSSH, no repo script.

   ```bat
   ssh-keygen -t ed25519 -f "%USERPROFILE%\.ssh\homelab_pve01_ed25519"
   ```

   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/homelab_pve01_ed25519
   ```

7. Write the secret files whose writer is the operator. Role: operator (WSL). The editor opens the decrypted file; a new file must match a path rule of `.sops.yaml`. The root password is a fresh random value, never typed on a command line.

   - `iac/secrets/hosts/pve01.sops.yaml`: `root_password`
   - `iac/secrets/hosts/pve01-access.sops.yaml`: `root_authorized_keys`, `root_authorized_keys_revoked`, `automation_authorized_keys` (public keys)
   - `iac/secrets/hosts/pve01-network.sops.yaml`: `host_routed_prefixes`, taken from `StaticDenyPrefix` of the local override `%LOCALAPPDATA%\homelab\pve01.local.psd1` once it exists (2.3 step 3)

   ```sh
   sops iac/secrets/hosts/pve01.sops.yaml
   sops iac/secrets/hosts/pve01-access.sops.yaml
   sops iac/secrets/hosts/pve01-network.sops.yaml
   ```

State root for OpenTofu, once (operator, WSL):

```sh
sudo install -d -o "$USER" -m 0700 /var/lib/homelab/tofu
```

### 2.2 Prepared install ISO

| # | Step | Role | Command or check |
|---|---|---|---|
| 1 | Download the stock Proxmox VE 9.1-1 installer ISO (a 9.2 ISO is reported not to boot on Hyper-V Generation 2, ADR 0004, row 11, 9.2 installer fails on Hyper-V; row 30, installer bug report) and verify it against the publisher's `SHA256SUMS` and its signature by hand | operator | `sha256sum <iso>` equals the published value |
| 2 | Render the answer file from `iac/proxmox/answer.pve01.toml.tmpl` (root hash from SOPS through a pipe, MAC and addresses from `scripts/hyperv/pve01.psd1`), validate it and write the prepared ISO | operator (WSL) | `bash scripts/proxmox/build-auto-install-iso.sh --source-iso <stock iso> --pubkey-operator <Windows key .pub> --pubkey-automation <WSL key .pub> --output <WSL form of %LOCALAPPDATA%>/homelab/iso/<prepared>.iso` (add `--force` to overwrite). It prints `validate-answer exit=0` and the prepared ISO's sha256 |

The prepared ISO holds the root-password hash: it is deleted after the install (2.3) and never copied elsewhere.

### 2.3 The PVE VM (Hyper-V)

All lines are for `cmd.exe` at the repository root. Preview first, then the real run.

| # | Step | Role | Command or check |
|---|---|---|---|
| 1 | Preview, changes nothing, writes no file | operator (Windows) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -InstallIso "%LOCALAPPDATA%\homelab\iso\<prepared>.iso" -InstallIsoSha256 <64 hex> -Install -PlanOnly` |
| 2 | Real run, one elevated pass: host rights, folder and ACL, switch, NAT, VM, port ACLs, install, wait for power-off, eject the ISO, checkpoint `post-install`, start, wait for TCP 22, delete the ISO copy. Install 459 s, first cold boot 18.1 s (row 35, unattended install). The transcript goes to `%LOCALAPPDATA%\homelab\logs\New-PveHost-<timestamp>.log` | owner (elevated prompt, accepts UAC) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -InstallIso "%LOCALAPPDATA%\homelab\iso\<prepared>.iso" -InstallIsoSha256 <64 hex> -Install` |
| 3 | Exit 2 means Hyper-V was just enabled and a Windows restart is needed (the script never reboots): restart, then repeat step 2. After the first run the local override file exists; copy its `StaticDenyPrefix` into `pve01-network.sops.yaml` (2.1 step 7) | owner | exit codes in `scripts/hyperv/README.md` |
| 4 | Sign in again so the Hyper-V Administrators membership takes effect, then check | operator (Windows) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1 -Action Status` |
| 5 | Trust the host key once through the Windows OpenSSH client (compare the fingerprint it prints with the install transcript), then store the public key as the pinned host key. No repo script; the block below the table combines the proxy command of `render-ssh-config.sh` with the pipeline of 2.9 step 8 and has no recorded run of its own. If the Windows client cannot prompt from WSL, run its `ssh.exe` part once in a Windows prompt, accept the key, then repeat | operator (WSL) | the block below the table |
| 6 | Render the SSH config and the pinned `known_hosts` | operator (WSL) | `bash scripts/iac/render-ssh-config.sh` (it prints `rendered N host(s)`) |
| 7 | Restore point before the first converge, with the VM stopped (ADR 0019) | operator (Windows) | `Invoke-PveVm.ps1 -Action Stop`, then `-Action Checkpoint -Name pre-converge`, then `-Action Start` (full command form in 3.1) |

Step 5 command (WSL):

```sh
winhome="$(cd /mnt/c && /mnt/c/Windows/System32/cmd.exe /c 'echo %USERPROFILE%' | tr -d '\r' | tr '\\' '/')"
/mnt/c/Windows/System32/OpenSSH/ssh.exe -i "$winhome/.ssh/homelab_pve01_ed25519" root@10.99.0.2 'cat /etc/ssh/ssh_host_ed25519_key.pub' \
  | awk '{print "ssh_host_ed25519_public: " $1 " " $2}' \
  | sops encrypt --filename-override iac/secrets/hosts/pve01-ssh.sops.yaml --input-type yaml --output-type yaml --output iac/secrets/hosts/pve01-ssh.sops.yaml /dev/stdin
```

The isolation layer, the firewall rule and the limits of the port ACLs are described in `scripts/hyperv/README.md`; a checkpoint taken before a credential rotation still holds the old secrets (3.1).

### 2.4 Host converge

| # | Step | Role | Command or check |
|---|---|---|---|
| 1 | First contact as root: switch the Proxmox repositories, create the automation user | operator (WSL) | `bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root` |
| 2 | Steady state as the automation user: roles `base`, `hyperv_guest`, `pve_host`, `pve_api_identity`, `pve_firewall`, `pve_templates`. Run 1 of the upgrade and baseline took 254 s including the reboot into the new kernel (row 43, converge run) | operator (WSL) | `bash scripts/iac/ansible.sh site.yml` |
| 3 | Idempotence: the second run must end `changed=0` (row 60, idempotence held) | operator (WSL) | `bash scripts/iac/ansible.sh site.yml` |

- A converge applies pending upstream updates and reboots the host when the running kernel is not the boot default (role `pve_host`, decision D40, package repository switch and upgrade). With runners present, drain the pool first or converge in a maintenance window.
- The SSH hardening runs behind a dead-man timer that restores the previous access if a step fails (ADR 0023). If a run stops while the timer is armed, the next run refuses to start: inspect the host and `journalctl -t homelab-deadman`, then delete the `armed` marker (`iac/ansible/README.md`, "SSH change guard").
- The first converge also starts the first build of every template class in the background, and the API token is written to `iac/secrets/tofu/pve01-api.sops.yaml` by the role. Commit the encrypted file.

### 2.5 OpenTofu host stack (guest network)

Role: operator (WSL). The wrapper opens the SSH forward, decrypts secrets into the `tofu` process only and keeps encrypted state on the WSL filesystem (ADR 0013, ADR 0029).

```sh
bash scripts/iac/tofu.sh proxmox-host pve01 init-passphrase     # once; writes iac/secrets/tofu/pve01-state.sops.yaml, commit it
bash scripts/iac/tofu.sh proxmox-host pve01 init
bash scripts/iac/tofu.sh proxmox-host pve01 plan
bash scripts/iac/tofu.sh proxmox-host pve01 apply
bash scripts/iac/tofu.sh proxmox-host pve01 plan -detailed-exitcode     # must return 0
```

`apply` and `destroy` first run `sudo -n ifquery --check -a` on the host and refuse on drift, because the SDN applier reloads the whole network config. The plan creates the `guests` vnet and the `cache` vnet (inventory `guest_network` and `cache_network`).

Verify on the host, read-only (`$pve`):

```sh
$pve bridge -d link show
$pve sudo iptables -t nat -S POSTROUTING
$pve sysctl -n net.ipv4.ip_forward
$pve cat /proc/sys/net/ipv4/conf/cache/forwarding
```

Expected: every guest port `isolated on`, a SNAT rule for each guest subnet (the cache subnet rule is `-s 10.99.17.0/24 -o vmbr0` only, row 61, cache network), `ip_forward` 1, cache forwarding 1.

### 2.6 Guard and firewall checks

Role: operator (WSL). The converge installs the firewall groups `guest-egress` and `cache-ingress`, writes `cluster.fw` and `host.fw` behind a dead-man, and arms the guard timer (ADR 0025, 0027, 0037, 0047).

```sh
$pve sudo systemctl is-active homelab-guest-firewall-guard.timer
$pve sudo journalctl -u homelab-guest-firewall-guard.service -n 3 --no-pager
$pve sudo sed -n '/^\[group/,$p' /etc/pve/firewall/cluster.fw
$pve sudo pveum acl list
bash tests/isolation/test-cluster-fw-render.sh
```

Expected: `active`; the last guard line `guest-firewall-guard: ok, N guest(s) checked on pve01`; both groups present; `/pool/templates` carries `HomelabTemplateClone`; the render test passes. Reading the guard output is in 3.6.

### 2.7 Golden templates

Build framework and per-step detail are in 3.3. From zero:

| # | Step | Role | Command or check |
|---|---|---|---|
| 1 | The first converge (2.4) deployed the bundles and base images and started a build per class. Follow it | operator (WSL) | `$pve sudo journalctl -f -u 'homelab-template-build@*'` |
| 2 | Every class has exactly one `current`; build times are in `docs/handoff/results.md` | operator (WSL) | `$pve sudo homelab-template status` exits 0 |
| 3 | A failed or missing build is rebuilt with the unit | root on pve01 | `$pve sudo systemctl start --no-block homelab-template-build@lxc-runner.service` (or `vm-docker`) |

### 2.8 R15 verification (probe stack and `r15-verify.yml`)

R15 is the isolation proof: runner-class guests must not reach management, other guests or private networks. The probe guests are two linked clones of the current templates (`r15-probe-lxc-runner-v<N>`, VMID 9101; `r15-probe-vm-docker-v<N>`, VMID 9102; pool `homelab`; ADR 0031, 0032, 0044). The probe reaches its clones through a probe-only channel; templates stay sealed.

| # | Step | Role | Command or check |
|---|---|---|---|
| 1 | Storage `local` allows snippets | operator (WSL) | `$pve sudo pvesm status --content snippets` lists `local` |
| 2 | Windows-side paired controls: copy `tests/isolation/targets.example.env` to `tests/isolation/targets.env` (git ignores it), fill it, then run the controls and copy the `True` rows into the `control` column | operator (Windows) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Test-R15Controls.ps1` |
| 3 | Create the ephemeral key and the vendor-data snippet on the host; it prints `TF_VAR_probe_ssh_public_key=...` | operator (WSL) | `bash scripts/iac/ansible.sh r15-verify.yml -l pve01 --tags r15_keygen` |
| 4 | Create the clones (run step 3 first or the VM clone fails to start) | operator (WSL) | `export TF_VAR_probe_ssh_public_key='ssh-ed25519 ...'`, then `bash scripts/iac/tofu.sh r15-probe pve01 init` and `bash scripts/iac/tofu.sh r15-probe pve01 apply` |
| 5 | Prove the clones are linked clones of the templates | operator (WSL) | `$pve sudo pct config 9101` and `$pve sudo qm config 9102` list no `template:`; `$pve sudo lvs -o lv_name,origin pve` shows an `origin` of `base-<template vmid>-disk-N` |
| 6 | Run the baseline phase: every `PROBE` row holds and `SUMMARY` exits 0. Counts at the reference end state are in `docs/handoff/results.md` | operator (WSL) | `bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<results directory>` |
| 7 | Phases `red-first` (attended, stops the node firewall, a timer restarts it after 10 minutes), `after-pct-reboot`, `after-pve-reboot`, `after-host-reboot` | operator (WSL) | the same command with `-e r15_phase=<phase>`; order and reading in `tests/isolation/README.md` |
| 8 | Tear down | operator (WSL) | `bash scripts/iac/tofu.sh r15-probe pve01 destroy`, then `$pve sudo rm -f /root/.ssh/r15_probe_ed25519 /root/.ssh/r15_probe_ed25519.pub /var/lib/vz/snippets/r15-probe-vendor.yaml /var/lib/homelab/r15/known_hosts` |

Read raw probe records only from the output file, never echo them to a terminal (`docs/knowledge/real-host-defects.md`, last row of phase 4). While a probe clone of template version N exists, retention refuses to delete version N: destroy the probe first.

### 2.9 Cache service (`build-cache-debian-13`, VMID 9050, vnet `cache`)

A bazel-remote container on its own routed vnet serves content-addressed caches to the runners through one firewall path, tcp 10.99.17.10:8080. Reads are anonymous; writes need the one writer credential, which only default-branch push jobs in the environment `cache-writer` receive (ADR 0045 to 0051). The inventory and SSH alias is `build-cache`; the host-key pin file keeps its name `iac/secrets/hosts/cache01-ssh.sops.yaml`. Role for every step: operator (WSL) unless named.

1. Offline gate.

   ```sh
   bash tests/isolation/test-cluster-fw-render.sh
   bash tests/isolation/test-guest-fw-guard.sh
   bash tests/isolation/test-r15-probe.sh
   bash tests/isolation/test-r15-verify-cache.sh
   ansible-lint --profile production iac/ansible
   ```

2. On a host that already runs guests, list guests on any bridge other than `guests` and `cache`; the guard stops them once its per-vnet policy is in place (ADR 0047). Skip on a fresh host.

   ```sh
   $pve sudo grep -l 'bridge=vmbr0' /etc/pve/qemu-server/*.conf /etc/pve/lxc/*.conf
   ```

3. The converge (2.4) and the host stack (2.5) already rendered `guest-egress` with the cache accept first, the group `cache-ingress`, the guard policy `/etc/homelab/guest-firewall-guard-policy.json`, the `SDN.Use` grant on `/sdn/zones/hlab/cache` and the `cache` vnet. Rerun them only if one is missing.

   ```sh
   bash scripts/iac/ansible.sh site.yml
   bash scripts/iac/tofu.sh proxmox-host pve01 plan -detailed-exitcode
   ```

4. Writer credential, once. The script writes `iac/secrets/hosts/pve01-cache.sops.yaml` and sets the environment secret `CACHE_WRITER_PASSWORD` in `cache-writer` from stdin, printing names only. Commit the SOPS file. WSL needs a `gh` command; this wrapper at `~/.local/bin/gh` execs the Windows client (adjust the path to your `gh.exe`):

   ```sh
   #!/bin/sh
   export WSLENV="GH_TOKEN/u${WSLENV:+:$WSLENV}"
   exec "/mnt/c/Program Files/GitHub CLI/gh.exe" "$@"
   ```

   ```sh
   bash scripts/iac/cache-writer-secret.sh --repo <owner>/<repository>
   ```

5. Owner, GitHub setting, no command: Settings, Environments, `cache-writer`, Deployment branches and tags, Selected branches, `master`. Until it is set, any branch's workflow that names the environment receives the secret (ADR 0050). Set on this repository 2026-10-08.

6. Create the container, stopped.

   ```sh
   export TF_VAR_ssh_public_keys='["<automation public key>"]'
   bash scripts/iac/tofu.sh cache-service pve01 init
   bash scripts/iac/tofu.sh cache-service pve01 plan
   bash scripts/iac/tofu.sh cache-service pve01 apply
   ```

7. Run only the start-gate play, which reads back the container's firewall and starts it only if every setting holds.

   ```sh
   bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml -l pve01
   ```

8. Pin the container's host key through the root path on pve01, render the SSH config and test the login.

   ```sh
   $pve sudo pct exec 9050 -- cat /etc/ssh/ssh_host_ed25519_key.pub \
     | awk '{print "ssh_host_ed25519_public: " $1 " " $2}' \
     | sops encrypt --filename-override iac/secrets/hosts/cache01-ssh.sops.yaml --input-type yaml --output-type yaml --output iac/secrets/hosts/cache01-ssh.sops.yaml /dev/stdin
   bash scripts/iac/render-ssh-config.sh
   ssh -F ~/.config/homelab/ssh_config build-cache true
   ```

   Expected: `rendered N host(s)` and the login exits 0.

9. Converge the service; the second run must end `changed=0`.

   ```sh
   bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml
   ```

10. Verify from a guest on the runner subnet (the workstation is not admitted on 8080): anonymous `GET /cas/<sha256>` 404 then 200 after a write, anonymous `PUT` 401, writer `PUT` 200, a `PUT` whose body does not match its digest 500 with nothing stored, `/metrics` shows `bazel_remote_disk_cache_size_bytes_limit 8.589934592e+09` (row 62, cache API). The transcript is `docs/evidence/phase4/cache-api.txt`.

11. R15 with the cache path: the baseline of 2.8 step 6 reaches the cache (positive) and drops its tcp/22 (negative); `r15-verify.yml` probes the cache container automatically when the host entry has `cache_endpoint`.

`site.yml` never touches the cache container; `cache.yml` does.

### 2.10 Create a guest from a flavor

A guest sized by a cloud flavor from `iac/tofu/flavors.json` (ADR 0055). Role: operator (WSL). The guest is a linked clone of the `current` template of its class, created stopped, named `<role>-<class>-v<N>` (`N` is the cloned template version) and tagged `flavor-guest`, `flavor-<provider>-<instance>` and `src-<class>-v<N>`. A slot from 1 to 99 fixes its VMID (9500 plus the slot) and address (host 100 plus the slot of the guest subnet). A worked example with real output is in `docs/handoff/examples.md`.

1. Plan without applying. The command adds the guest to `iac/tofu/stacks/guest/guests.yml`, then runs `init` and `plan`.

   ```sh
   bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo
   ```

   Expected first line: `guest demo-lxc-runner on pve01: aws/t3.medium, lxc-runner, slot 1`, then a plan that only adds.

2. Apply. The command applies with `-auto-approve`, then runs `plan -detailed-exitcode`; while the plan still shows changes it applies once more, and fails if the second plan still does. A container clone ignores the flavor disk size on its first apply, so the second apply is expected for `lxc-runner` (`docs/knowledge/real-host-defects.md`).

   ```sh
   bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo --apply
   ```

3. Check the sizes on the host.

   ```sh
   $pve sudo pct config 9501
   ```

   Expected: `cores: 2`, `memory: 4096`, a `rootfs` of 30 GiB, the three tags and `bridge=guests,firewall=1`. For a VM use `$pve sudo qm config <vmid>`.

To remove a guest, delete its entry from `guests.yml` and run `bash scripts/iac/tofu.sh guest pve01 apply`. Updating a role and class keeps its slot; omitting `--version` returns the guest to the current template.

## 3. Day-2 operations

### 3.1 The VM: start, stop, status, checkpoint

Role: operator (Windows), non-elevated once the Hyper-V Administrators membership is active. Prefix every line with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\Invoke-PveVm.ps1`.

| Action | Command suffix | Behavior |
|---|---|---|
| Status | `-Action Status` | state, reachability, adapter connection, ACL rule counts, foreign ACLs, egress interface, firewall rule |
| Start | `-Action Start` | checks host RAM and the firewall rule (refuses unless `-Force`), refreshes the port ACLs, starts the VM, prints seconds until TCP 22 answers (about 16 s, row 45, checkpoint action) |
| Refresh | `-Action Refresh` | running VM only: re-syncs the port ACLs after a VPN or default-route change; exit 1 and a disconnected adapter if the sync fails |
| Stop | `-Action Stop` | graceful with a timeout; a hard power-off needs `-TurnOff -Force` |
| Checkpoint | `-Action Checkpoint -Name <name>` | only while the VM is `Off`, the name unused, no DVD media attached, enough free disk (ADR 0019) |

- There is no restore action. Restore with Hyper-V Manager or `Restore-VMSnapshot`, then start only with `-Action Start`: it re-syncs the port ACLs, a start from Hyper-V Manager does not. Remove a restore point (`Remove-VMSnapshot`) once the step it protects is verified.
- A checkpoint taken before a credential rotation still holds the rotated-away secrets and restoring it makes them live again: take a fresh checkpoint after every rotation and remove the older ones.
- Known gap: a scheduled task that runs `Refresh` on network change is required before any runner registers and is not created by the scripts (`scripts/hyperv/README.md`). Until it exists, a VPN or default-route change while the VM runs is picked up only by a manual `Refresh` or `Start`.
- After docking or a network switch, a default route on another interface denies all guest egress (fail closed): edit `EgressInterfaceAlias` in the local override, then `Refresh`.
- Rollback of the whole VM setup (owner, elevated): `New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -Uninstall`; add `-PlanOnly` to list what would go.

### 3.2 Converge and the reboot caveat

```sh
bash scripts/iac/ansible.sh site.yml          # host baseline, role by role; second run changed=0
```

A converge with pending kernel updates reboots the host: the cluster firewall, the guard and every guest stop and restart. After a reboot SSH answered at 43 s, the cache container ran at 45 s and its service at 49 s with data intact (row 67, reboot timings). Do it with the VM idle: no template build, no probe run, no runner job. Stop and take a checkpoint first (3.1) when the change is risky.

### 3.3 Golden templates

Classes: `lxc-runner` (VMID block 9200-9299) and `vm-docker` (9300-9399). A build is run by root on the host; the sandboxed guest step does the in-guest work (ADR 0038). Retention keeps `current` and `previous` (ADR 0039). A weekly timer rebuilds both classes; a build of a class also starts after a converge that changed its `versions.yml` (ADR 0041).

Build, role root on pve01 (use the unit, not the bare command, so a failure marker is written):

```sh
$pve sudo systemctl start --no-block homelab-template-build@lxc-runner.service      # or vm-docker
$pve sudo journalctl -f -u homelab-template-build@lxc-runner.service -u homelab-template-guest@build.service -u homelab-template-guest@verify.service
```

Journal order on success: `PREFLIGHT ok`, `BUILD start ... version=v<N>`, `READBACK ok ... before first start`, `GATE ok ... manifest_sha256=...`, `VERIFY ok clone=<id> is a linked clone`, `PROMOTED class=... v<old> -> v<new>`, `RETENTION`. A failure ends with `FAILED` or `REFUSED` and the reason.

Status, rollback, repair (root on pve01):

```sh
$pve sudo homelab-template status                  # exit 0 only when every class has exactly one current
$pve sudo homelab-template rollback lxc-runner     # swaps current and previous; running again swaps back
$pve sudo homelab-template repair lxc-runner       # re-tags from the root state after a failed tag move
```

`class=<c> ERROR current-count=0` or `=2` means consumers refuse the class; `MISMATCH recorded=<n>` means tags differ from the root state, run `repair`. After a rollback the next build promotes on top of the rolled-back version. Running clones are not touched. Measured: two versions per class retained, one-command rollback (row 56, retention and rollback).

Recover a failed build: read the marker (`$pve sudo ls /var/lib/homelab/templates/failed/`), then the cause (`$pve sudo journalctl -u homelab-template-build@<class>.service -n 200`, and `-u homelab-template-guest@build.service` for the guest step). Match the last line:

| Line says | Action |
|---|---|
| `REFUSED thin pool ... is above` or `storage local has ... GiB free` | free space, rebuild; thresholds are `pve_templates_thresholds` in `iac/ansible/roles/pve_templates/defaults/main.yml` (thin pool 70 percent, local 8 GiB free) |
| `REFUSED another homelab-template run holds the lock` | a build is running: `$pve sudo systemctl status homelab-template-build@<class>.service` |
| `pre-start read-back differs: ...` | fix the named setting in the role or `iac/policy/runner-class.yml`, converge, rebuild |
| `pass marker ... missing`, `guest-step: in-guest run.sh exited`, `SCAN FAILED` | read the guest-step lines above it, fix the class content, rebuild |
| `not a linked clone` or `clone check differs` | rebuild |
| `promotion recorded in state but the tag move failed` | `$pve sudo homelab-template repair <class>`, then `status` |

Leftover guests need no manual cleanup: the next build destroys any non-template guest in the class block.

Timer and last build: `$pve systemctl list-timers homelab-template-weekly.timer`, `$pve sudo journalctl -u 'homelab-template-build@*' -u homelab-template-weekly.service --since "7 days ago"`, `$pve systemctl list-units 'homelab-template-failure@*' --all`. A failed build leaves a `homelab-template-failure@<class>` run while the weekly service still ends green.

Where things live on pve01: `/usr/local/sbin/homelab-template`, `/etc/homelab-template/config.json` (rendered, do not edit), root state `/var/lib/homelab/templates/<class>.json`, manifests `/var/lib/homelab/templates/manifests/<class>/v<N>.json`, failure markers `/var/lib/homelab/templates/failed/<class>`.

Bump a base image pin (operator, WSL; then converge as root through Ansible):

1. Take the new file name and its sha512 from the vendor index (`SHA512SUMS` beside the Debian cloud image; the Proxmox template mirror index). Debian images use a dated directory, never `latest`.
2. Edit `pve_templates_base_images` (`url`, `sha512`) and `base:` in `pve_templates_classes` in `iac/ansible/roles/pve_templates/defaults/main.yml`; the role asserts the url file name equals the base volume name.
3. Pull request and merge, then `bash scripts/iac/ansible.sh site.yml -l pve01`. The old image stays on the host until removed by hand, after the class built from the new one.
4. Bump the class `versions.yml` when the new image should produce a new template; the converge starts that build.

Bump a pinned toolchain in `lxc-runner` (operator with write access, branch and pull request). Edit only `iac/ansible/roles/pve_templates/files/bundles/lxc-runner/versions.yml` (plus `scan-allowlist.txt` when the scan asks). Each bump changes `version`, `url` and the hash together.

1. .NET SDK (`dotnet_sdk_8`, `dotnet_sdk_10`): `curl -fsSL https://builds.dotnet.microsoft.com/dotnet/release-metadata/8.0/releases.json -o releases-8.0.json` (use `10.0` for the other), then `jq -r '.releases[0].sdk.files[] | select(.rid=="linux-x64" and (.name|test("tar.gz"))) | .url, .hash' releases-8.0.json`. The hash is sha512. Check the downloaded file with `sha512sum`. `dotnet_sdk_8` has an `end_of_support` date (2026-11-10); remove it and its playbook assert in a pull request after the repository stops targeting 8.0.x.
2. Node 22 (`nodejs`): `curl -fsSLO https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt` and `SHASUMS256.txt.asc`; read the version from the file names and pin the exact version, never the `latest-v22.x` path. Verify `gpg --verify SHASUMS256.txt.asc SHASUMS256.txt` against the Node release keys, on the operator machine and never on pve01. The sha256 is `grep 'node-v<version>-linux-x64.tar.gz$' SHASUMS256.txt`.
3. `actions_runner`: `gh api repos/actions/runner/releases/latest --jq .body`; take the sha256 between `BEGIN SHA linux-x64` and `END SHA linux-x64`. The service stops queuing jobs to a runner more than 30 days behind a critical release, so bump within the month.
4. Local check, must end `OK:`: `bash tests/isolation/test-template-content.sh`.
5. If a build stops with `SCAN FAILED ... secret pattern: <path> sha256=<hash>` for a file inside a Node or runner directory, open the file. Only the npm config help text or the definitions file with a placeholder key is allowlisted, by adding `<sha256>  <path>` to `scan-allowlist.txt` in the same pull request; any other file is a finding.
6. Merge, converge (`bash scripts/iac/ansible.sh site.yml -l pve01`) or wait for the weekly timer. The build fails when installed versions differ from `versions.yml`.
7. Verify: the new version's manifest `toolchains` and `versions_sha256` equal `sha256sum versions.yml` of the merged commit.

Bump the `vm-docker` class (`iac/ansible/roles/pve_templates/files/bundles/vm-docker/versions.yml`):

1. Engine: on a Debian 13 host run `apt-cache policy docker.io containerd runc` after `apt-get update`, then edit the `version:` of those three entries under `apt_packages`.
2. Runner: take the `linux-x64` sha256 from the runner release notes, edit `version`, `url` and `sha256` of `actions_runner` (the version appears in the url twice), then check `curl -sLO <url>` against `sha256sum <file>`.
3. `bash tests/isolation/test-template-content-vm.sh` must print `all passed`; commit, pull request, merge; the next rebuild picks it up (`$pve sudo homelab-template build vm-docker` builds now).
4. Check the class on a clone with the R15 probe stack (2.8 steps 3 and 4), then, with `c` set to `$pve sudo ssh -i /root/.ssh/r15_probe_ed25519 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new debian@10.99.16.22`: `$c 'sudo docker run --rm hello-world'` prints "Hello from Docker!"; `$c "grep -cE 'svm|vmx' /proc/cpuinfo"` prints 0; `$c 'ls /opt/actions-runner/.runner /opt/actions-runner/.credentials'` reports both missing; `$c 'ss -ltn | grep -c :2375'` prints 0; `$c 'sudo -n -l -U runner'` says the runner user may not run sudo (row 59, clone isolation). Tear down as 2.8 step 8.

Consume or pin a template (operator, WSL): a consumer never names a VMID; the module `iac/tofu/modules/proxmox/template-source` resolves the one template that carries the marker `homelab-template`, the class and the tag `current`, is a member of pool `templates` and lies in the class block, or the plan stops (ADR 0044).

```sh
$pve sudo homelab-template status
bash scripts/iac/tofu.sh r15-probe pve01 plan                 # the template_sources output lists class to VMID
export TF_VAR_template_pins='{"lxc-runner":1}'                # pin class to version N; the version must still exist
bash scripts/iac/tofu.sh r15-probe pve01 apply                # replaces the guest, the provider forces a new one
unset TF_VAR_template_pins                                    # follow current again
```

Rollback by pin changes one consumer, needs no host access and survives a new build; the root `rollback` moves `current` for every consumer. Errors: `Expected exactly one <class> template ... found 0` means no `current` (a build is running or none was built); `found 2` means run `homelab-template repair <class>`.

### 3.4 Cache: health, purge, rotation

Role: operator, reaching the cache container as root: `ssh -F ~/.config/homelab/ssh_config build-cache`.

- Health: `systemctl status bazel-remote`; `journalctl -u bazel-remote -b | grep -E 'wait-for-address|verify-cas|Loaded'`. Every start runs `wait-for-address` (reads `/proc/net/fib_trie`; the unit's sandbox forbids netlink, so `ip` cannot be used there) and `verify-cas`, which hashes every blob and moves one whose content does not match its name to `/var/lib/bazel-remote/quarantine/`.
- Size and eviction: budget 8 GiB (`--max_size 8`) on a 10 GiB volume, LRU eviction; metrics `bazel_remote_disk_cache_size_bytes` and `..._evicted_bytes_total` on `/metrics` (row 62, cache API).
- Hit counting: Prometheus `bazel_remote_incoming_requests_total{kind="ac"}` does not count pointer lookups when AC validation is disabled; count from the access log (`journalctl -u bazel-remote | grep ' /ac/'`, status 200 hit, 404 miss) or from the client stats.
- Purge for a cold cache: `systemctl stop bazel-remote && find /var/lib/bazel-remote/data -mindepth 1 -delete && systemctl start bazel-remote`. Builds run cold until a default-branch push saves again.
- Rotate the writer credential (operator, WSL), then converge: `bash scripts/iac/cache-writer-secret.sh --rotate --repo <owner>/<repository>`, then `bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml`.
- Disable: empty `CACHE_URL` in `.github/workflows/reusable-sdet-pipeline.yml`; every restore answers "miss: no store configured" and builds run cold. Hosted runs already behave that way (row 68, hosted run with the cache disabled).
- Measured behavior: `docs/handoff/results.md`.

Client wiring (CI): `dotnet` (Build and Test) restores `nuget` then `dotnet-outputs`; `angular-jest` restores `node_modules`; the two `*-cache-save` jobs write only on a push to the default branch, in environment `cache-writer`. Statuses in the job summary: restore `hit`, `miss`, `rejected` (digest mismatch or unsafe archive; the build runs cold), `error`; save `saved`, `skipped`, `refused` (401 or 403), `failed` (5xx). No status fails a job. Keys are content-addressed and outputs are restored only on an exact match (ADR 0049).

### 3.5 Secrets rotation

| Secret | Command | Then |
|---|---|---|
| Cache writer credential | `bash scripts/iac/cache-writer-secret.sh --rotate --repo <owner>/<repository>` (operator, WSL) | converge `cache.yml` (3.4); fresh VM checkpoint if the VM was checkpointed earlier |
| OpenTofu API token | `bash scripts/iac/ansible.sh site.yml -l pve01 -e pve_api_identity_rotate=true` (the role replaces the privilege-separated token and writes `iac/secrets/tofu/pve01-api.sops.yaml` through `sops set --value-stdin`) | commit the encrypted file |
| OpenTofu state passphrase | move the encrypted state aside, then `bash scripts/iac/tofu.sh proxmox-host pve01 init-passphrase --rotate`; `tofu.sh` refuses while the state is still encrypted with the current passphrase | recreate or import the state; the stacks share the host's passphrase |
| R15 probe key | delete `/root/.ssh/r15_probe_ed25519` on the host, rerun `bash scripts/iac/ansible.sh r15-verify.yml -l pve01 --tags r15_keygen`, replace the VM clone | the keygen play also clears the previous probe host keys |
| Root password, SSH keys | edit with `sops iac/secrets/hosts/pve01.sops.yaml` and `pve01-access.sops.yaml`, then converge `site.yml` (keys); the root password reaches the host and every running guest with `bash scripts/iac/ansible.sh iac/ansible/playbooks/lab-accounts.yml -i iac/inventory/hosts.yml` | take a fresh checkpoint, remove the old ones; reboot each guest-stack VM, which takes it at boot |
| Visitor password (`guest@pve` and the local `guest`) | `printf '"%s"' '<new value>' \| sops set --value-stdin iac/secrets/hosts/pve01-lab-accounts.sops.yaml '["guest_password"]'` from a shell that keeps no history, then the same playbook | reboot each guest-stack VM |
| age identity (leak or loss) | a leaked identity means change every secret value, not only the encryption: old commits stay decryptable. New values, new recipient in `.sops.yaml`, recommit, apply to the hosts | `iac/secrets/README.md`, "Recovery and rotation" |

Every secret file has one writer (table in `iac/secrets/README.md`). Never print a secret or put one on a command line; the scripts above read and write secrets through stdin.

Logins for visitors (ADR 0059): web UI user `guest`, realm "Proxmox VE authentication server"; console of any guest, user `guest`. Root: web UI user `root`, realm "Linux PAM"; console of any guest, user `root`. A second run of `lab-accounts.yml` reports `changed=0` on the host, the containers and the probe VM.

### 3.6 The guest firewall guard

A root-owned timer (`homelab-guest-firewall-guard.timer`, one-minute cadence) runs `/usr/local/sbin/homelab-guest-firewall-guard` against the policy in `/etc/homelab/guest-firewall-guard-policy.json`. It stops any guest on a guarded vnet whose firewall settings are not the required policy: NIC without `firewall=1`, `policy_out` not DROP, a disabled group rule, an extra enabled rule, or inbound tcp/22 from a non-gateway source. It never starts a guest. Guests on an unknown bridge or on the host bridge are stopped too.

```sh
$pve sudo journalctl -u homelab-guest-firewall-guard.service -n 20 --no-pager
$pve sudo ls /var/lib/homelab/guest-firewall-guard/violations
```

| Output | Meaning | Action |
|---|---|---|
| `guest-firewall-guard: ok, N guest(s) checked on pve01` | every guest on a guarded vnet complies | none |
| `VIOLATION vmid=<id> type=<t> <reason>; stopped` | the guest was stopped; a marker is left under `violations/<id>` | fix the guest's firewall (read the reason), then start it |
| `VIOLATION ... STOP FAILED` | the guard could not stop it, exit 4 | stop it by hand now: `$pve sudo qm stop <id>` or `pct stop <id>` |
| a capitalised line with `vmid=<id> type=<t> run=<n>/<limit> (<error>)` | the guest's config could not be read; the run counts toward a limit of 3 (`pve_firewall_guard_*` in `iac/ansible/roles/pve_firewall/defaults/main.yml`), exit 4 | check `pvesh get` on the guest |
| `ERROR cannot read the policy` or `cannot list guests`; no guest was stopped | the guard is blind, exit 4 | rerun `site.yml`; check `pvesh` |

A container created before its firewall exists is flagged at once; create guests stopped and start them only after a firewall read-back (the cache container does, ADR 0047, row 62, cache API).

### 3.7 The CI runner (`ci-lxc-runner-v6`, VMID 9503)

One unprivileged container from `lxc-runner`, flavor `aws/c5.2xlarge` (8 cores, 16 GiB), entry `ci-lxc-runner` in `iac/tofu/stacks/guest/guests.yml` (slot 3; create it as in 2.10). It runs three runner instances, `pve01-ci-lxc-runner-1` to `-3`, from `/opt/actions-runner-N` as the user `runner`, which has no sudo. Labels: `self-hosted`, `linux`, `proxmox`, `dotnet`, `angular` (ADR 0060).

1. Register and converge. Role: operator (WSL), with a token of an account that administers the repository.

   ```sh
   GH_TOKEN="$(gh auth token)" bash scripts/iac/ansible.sh iac/ansible/playbooks/ci-runner.yml -i iac/inventory/hosts.yml
   ```

   Expected: the last task lists three runners `online`; a second run reports `changed=0`. The registration token goes to `config.sh` on stdin and never appears in a log.

2. Route CI. `sdet-ci.yml` uses the runner when the repository variable `CI_RUNNER` is `proxmox`; any other value, or no variable, means hosted runners. Fork pull requests always run hosted.

   ```sh
   gh variable set CI_RUNNER --body proxmox --repo <owner>/<repository>
   gh variable set CI_RUNNER --body hosted --repo <owner>/<repository>
   ```

   One hosted run without changing the variable: `gh workflow run sdet-ci.yml -f force_ubuntu_runner=true`.

3. Read a job. Every job on the runner starts with the job-start hook:

| Line in the job log | Meaning |
|---|---|
| `runner-guard: allowed <event> on <repository>` | the job runs |
| `runner-guard: refused: <reason>` | the job failed before its first step: a fork pull request, `pull_request_target`, another event or another repository |

Health, as root on the host:

```sh
$pve sudo pct exec 9503 -- systemctl status 'actions-runner@*' 'actions-runner-restart@*.path'
gh api repos/<owner>/<repository>/actions/runners -q '.runners[]|"\(.name) \(.status) busy=\(.busy)"'
```

After each job the job-completed hook writes `/run/actions-runner-N/restart`, and `actions-runner-restart@N.path` restarts that instance once its worker has exited. Without it the listener waits about 60 s before it takes the next job (actions/runner#4444).

When the container is down, routed jobs queue for up to 24 hours: set `CI_RUNNER` to `hosted` and re-run them. To retire the runner, set the variable to `hosted`, deregister the three runners (Settings, Actions, Runners), and stop the container; the lab does not destroy guests (D86).

### 3.8 The pull-request run report

`sdet-callback.yml` runs after every SDET pipeline run, on hosted runners, and keeps one comment on the run's pull request up to date (ADR 0061). The comment lists:
- per suite: passed, failed, skipped, the pass rate (passed over executed) and the execution rate;
- every failed test, with its message and stack;
- every job that failed outside the tests, with its failing step and the last 40 log lines.

A run with no open pull request at its head writes the same report to the callback's job summary.

| Task | Command |
|---|---|
| Report an older run again, or test a change to the callback before it merges | `gh workflow run sdet-callback.yml --ref <branch> -f run_id=<SDET run id>` |
| Turn the report off | `gh workflow disable sdet-callback.yml` |
| Check the parser offline | `python3 -m unittest discover -s tests/report -v` |

The callback runs the default branch's copy of the workflow. It never checks out the pull request's code, and it treats every file and log of the run as untrusted text.

## 4. Verification and evidence

### 4.1 Offline suites (no host)

Canonical command list; other pages link here. Operator (WSL), repository root, after step 3 of 2.1. CI runs the same checks (`docs/knowledge/test-catalogue.md` has what each test proves; `docs/knowledge/coverage.md` the coverage numbers).

```sh
for t in tests/isolation/test-*.sh; do bash "$t" || break; done            # isolation, role, template, cache-service and guest-wrapper tests
ansible-lint --profile production iac/ansible
for p in iac/ansible/playbooks/*.yml; do ANSIBLE_CONFIG=iac/ansible/ansible.cfg ansible-playbook --syntax-check "$p"; done
tofu fmt -check -recursive iac/tofu
(cd iac/tofu/stacks && tflint --recursive --config "$PWD/../../../.tflint.hcl")
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123      # any throwaway of 32 or more characters
for s in proxmox-host r15-probe cache-service guest; do tofu -chdir=iac/tofu/stacks/$s init -backend=false && tofu -chdir=iac/tofu/stacks/$s test; done
python3 -m pip install --require-hashes -r tests/cache/requirements-ci.txt
python3 -m unittest discover -s tests/cache -p "test_*.py"
python3 -m unittest discover -s tests/evidence -v
python3 standard/tests/test_scorecard.py
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac
bash tests/verify-affected-graph.sh
```

The Hyper-V module tests (Pester 5.7.1) need Windows; run them under both shells, from `cmd` at the repository root:

```bat
pwsh -NoProfile -File tests\hyperv\Invoke-HyperVTests.ps1 -PesterVersion 5.7.1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\hyperv\Invoke-HyperVTests.ps1 -PesterVersion 5.7.1
```

`bash tests/cache/test_stale_binaries.sh` needs Linux and the .NET SDK 8. The Molecule scenario of the `base` role needs a Docker daemon, so it runs only in CI: `cd iac/ansible/roles/base && molecule test`. CI workflows: `iac-ci.yml`, `cache-ci.yml`, `evidence-ci.yml`, `affected-selector-ci.yml`, `hyperv-ci.yml`, `standard-scorecard.yml`, `secret-scan.yml`.

What these prove is the logic and the unit files against fakes (`tests/isolation/lib/fake-pve.py`) and stubs, not Proxmox's or Hyper-V's behavior. A defect found only on the host is listed in `docs/knowledge/real-host-defects.md`.

### 4.2 Host proofs (real host)

| Proof | Command | Passes when |
|---|---|---|
| Idempotence | `bash scripts/iac/ansible.sh site.yml` twice | second run `changed=0` (row 60, idempotence held) |
| Host stack drift | `bash scripts/iac/tofu.sh proxmox-host pve01 plan -detailed-exitcode` | exit 0 |
| Templates | `$pve sudo homelab-template status` | exit 0, one `current` per class |
| Guard | `$pve sudo journalctl -u homelab-guest-firewall-guard.service -n 3 --no-pager` | ends `ok, N guest(s) checked` |
| R15 isolation | 2.8 step 6 | `SUMMARY` exits 0; counts at the reference end state are in `docs/handoff/results.md` |
| Cache | 2.9 step 10 | the six API outcomes hold (row 62, cache API) |
| Token boundary | provisioner token deletes or retags a template | 403; cloning it 200 (row 57, template protection) |

Two R15 rows stay not measured in every phase (a VPN peer's web service and a host in a harvested prefix): no positive control exists on the Windows side (`docs/knowledge/real-host-defects.md`, open findings).

### 4.3 Publishing evidence

Role: operator who holds the raw run output, on the workstation, Linux or WSL with Python 3.11 or newer, at the repository root. The raw files, the value map and the credential mask stay outside the repository; only the published copies and the index are committed (ADR 0052). The publish command with every selection file, the file formats and the checker rules are in `docs/knowledge/README.md`. Check what is committed, as CI does:

```sh
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac
```

## 5. Troubleshooting

Symptom, cause, fix. The full list with pull requests is `docs/knowledge/real-host-defects.md`.

| Symptom | Cause | Fix |
|---|---|---|
| `bootstrap.yml` or `site.yml` refuses to start, `armed` marker | an SSH-hardening run stopped while its dead-man was armed | inspect the host and `journalctl -t homelab-deadman`, delete the marker (2.4) |
| `site.yml must connect as the automation user` | `-e ansible_user=root` left on a steady-state run | drop it; only `bootstrap.yml` connects as root |
| Host rebooted during a converge | pending kernel update (decision D40, package repository switch and upgrade) | expected; schedule converges in a window (3.2) |
| Firewall check fires the dead-man on a clean config | a compile check read `ignore <chain>` lines as errors | fixed in the role; if it recurs, read `restore finished rc=0` in the journal and the check patterns |
| Probe VM create returns 403 | token lacked `Datastore.Audit` on the disk storage, or a tag was set on create | fixed in the role; never widen the token, the probe declares no tags |
| `unsafe characters in the Windows local application data path` on the second `apply` | the state copy path had a backslash | fixed: `tofu.sh` converts with `wslpath` |
| `unknown command` from a template build | a `pvesm` subcommand does not exist on the host | fixed: storage is read with `pvesh get /storage/<id>` |
| A converge failed and the rerun started no build | the on-change trigger was lost | fixed: a root-only pending-build marker survives until the build starts |
| `exit status 226/NAMESPACE` on the verify guest unit | a sandbox mount named a removed directory | fixed: the path entries are optional |
| VM build fails on an apt lock | cloud-init's first-boot `apt-get` holds it | fixed: `run.sh` waits for cloud-init |
| `Expected exactly one <class> template ... found 2` | a linked clone inherited the `current` tag | resolve only among pool `templates` (fixed); run `homelab-template repair <class>` |
| Clone's cloud-init drive returns 403 | the guest role lacked `VM.Config.CDROM` | fixed; granted on the guest role |
| Guard flags a new cache container at once | the container existed before its firewall | create stopped, start through the read-back gate (2.9 steps 6 and 7) |
| Cache write with a wrong digest answers 500 | bazel-remote 2.6.2 answers 500, not 400 | the client treats 500 or above as a failed write; the blob is never served |
| Cache serves a partial blob after `kill -9` | bazel-remote 2.6.2 does not verify a file on load | the `verify-cas` start step quarantines it |
| `bind: cannot assign requested address` on the first start after a reboot | the unit started before the address was configured | `wait-for-address` runs first and reads `/proc/net/fib_trie` |
| ssh to a re-created probe guest fails `REMOTE HOST IDENTIFICATION HAS CHANGED` | the previous generation's host keys were kept | the keygen play deletes the probe known-hosts file; rerun `--tags r15_keygen` |
| R15 `red-first` row fails `expected open, got dropped` after an SDN re-apply | the guest bridge's link-local address changed | update the stale address in `tests/isolation/targets.env` (open finding) |
| `ifquery --check -a` refusal on `apply` | network config drift on the host | fix the drift first; the SDN applier reloads the whole config |
| All guest egress denied after docking | a default route on another interface | edit `EgressInterfaceAlias`, then `Invoke-PveVm.ps1 -Action Refresh` |

## 6. Retired

The previous host (bare-metal Proxmox VE 8.x with persistent runner containers, an S3 cache and its bootstrap scripts) is retired; see ADR 0020 and the commit it names for what was kept.
