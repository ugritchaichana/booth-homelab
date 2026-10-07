# Build from zero

The order in which the reference implementation was built, each step with one command and the line that shows it worked. It is the outline for the Phase 8 timed rebuild, which has not been run: time the first rebuild and record every deviation. The full procedure for each step is in the [runbook](../../RUNBOOK.md) section named in the step heading; section 2 of the runbook follows this order. Worked examples with real output: [examples.md](examples.md).

## Prerequisites

| Need | Reference setup |
|---|---|
| A workstation that runs Hyper-V with nested virtualization | Windows 11 Pro, 8-core AMD CPU, 43.8 GiB RAM; nested KVM works with Memory Integrity on (row 36, nested KVM) |
| Budget for the PVE VM | 12 vCPU, 20 GiB static RAM, 128 GiB dynamic VHDX; C: keeps at least 20 GiB free (row 28, RAM headroom; row 29, disk headroom) |
| An operator shell with a Linux toolchain | WSL Debian (ADR 0010) |
| A repository the team administers, with `gh` authenticated | A fork of this one |
| New credentials for everything | Generated locally, never reused from this repository's history |

The SOPS files in `iac/secrets/` are encrypted to the reference operator's key. Create an age identity first, put its public recipient into `.sops.yaml`, then generate every value again (root password, API token, state passphrase, cache writer password). Keep an off-machine copy of the identity before the PVE install: a lost identity makes every secret unrecoverable ([secrets README](../../iac/secrets/README.md)).

## Steps

Roles: operator = WSL shell at the repository root; `$pve` = `ssh -F ~/.config/homelab/ssh_config pve01`.

### 1. Toolchain and age identity (operator; runbook 2.1)

```sh
sudo bash scripts/bootstrap/operator-toolchain.sh
```

Expected: a second run installs nothing and prints the version table. Done when `sops -d` of a test file works. ADR 0009, 0010.

### 2. Install ISO and the PVE VM (operator, host administrator; runbook 2.2 and 2.3)

```sh
bash scripts/proxmox/build-auto-install-iso.sh --source-iso <stock iso> --pubkey-operator <key.pub> --pubkey-automation <key.pub> --output <prepared>.iso
```

Expected: `validate-answer exit=0`. Then, from an elevated Windows prompt (`cmd`):

```bat
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\hyperv\New-PveHost.ps1 -ConfigPath scripts\hyperv\pve01.psd1 -InstallIso "%LOCALAPPDATA%\homelab\iso\<prepared>.iso" -InstallIsoSha256 <64 hex> -Install
```

Expected: exit 0. Done when `$pve pveversion` prints `pve-manager/9.` and the checkpoint `post-install` exists. Install took 459 s (row 35, unattended install). Guide: [scripts/hyperv/README.md](../../scripts/hyperv/README.md); ADR 0004, 0007, 0014.

### 3. SSH config and host converge (operator; runbook 2.3 steps 5 and 6, 2.4)

```sh
bash scripts/iac/render-ssh-config.sh
bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root
bash scripts/iac/ansible.sh site.yml
```

Expected: `rendered N host(s)` from the first command; a second `site.yml` run ends `changed=0`. Done when password login is refused and `hv_sock` is not loaded. [Ansible README](../../iac/ansible/README.md); ADR 0022, 0023, 0028.

### 4. API identity and firewall (operator; runbook 2.4 and 2.6)

Both are roles of the same converge.

```sh
$pve sudo systemctl is-active homelab-guest-firewall-guard.timer
```

Expected: `active`. Done when the provisioner token answers `/version` with 200 and refuses to create a user (403). ADR 0026, 0027.

### 5. Host OpenTofu stack (operator; runbook 2.5)

```sh
bash scripts/iac/tofu.sh proxmox-host pve01 apply
bash scripts/iac/tofu.sh proxmox-host pve01 plan -detailed-exitcode
```

Expected: the second command exits 0. Done when the state file is mode 600 and holds `encrypted_data` only. [OpenTofu README](../../iac/tofu/README.md); ADR 0013, 0030.

### 6. Golden templates (operator, root on pve01; runbook 2.7)

```sh
$pve sudo homelab-template status
```

Expected, one line per class: `class=lxc-runner current=v<N> vmid=<id> name=<name> previous=v<N-1> last_build=<time>`; exit 0. Done when each class holds two versions and a rollback moves `current` back and forward. Build times: [results.md](results.md). ADR 0038 to 0044.

### 7. Isolation proof (operator; runbook 2.8)

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<results directory>
```

Expected: `SUMMARY` with `negatives_blocked=19/19 positives_ok=2/2 egress_curl=200` for runner clones. Done when the red-first phase, with the PVE firewall stopped, shows the gateway and management rows open (the proof can fail). Guide: [isolation tests README](../../tests/isolation/README.md); ADR 0031, 0032, 0044.

### 8. Cache network and service (operator; repository administrator sets the environment branch policy; runbook 2.9)

```sh
bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml
```

Expected: a second run ends `changed=0`. Done when, from a runner clone, an anonymous read answers 404 then 200 and an anonymous write 401 ([cache-api.txt](../evidence/phase4/cache-api.txt)); R15 re-run includes the cache rows. ADR 0045, 0046, 0048, 0050.

### 9. Client wiring (operator; runbook 3.4)

```sh
bash tests/cache/test_stale_binaries.sh
```

Expected: the last line is `PASS`. Done when the hosted run is green with the cache disabled and an unchanged lockfile hits every restore on a runner-template clone. ADR 0049, 0053.

### 10. Evidence (operator; runbook 4.3)

```sh
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac
```

Expected: `checked N files: hard={}` and exit 0. [Knowledge README](../knowledge/README.md); ADR 0052.

### 11. A guest from a flavor (operator; runbook 2.10)

```sh
bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo --apply
```

Expected: `guest demo-lxc-runner on pve01: aws/t3.medium, lxc-runner, slot 1`. Done when the final plan exits 0 and R15 passes on the new guest. ADR 0055.

Re-run the R15 probe after every step that changes a firewall, a vnet, a template or the guard.

## Owner-only steps

| When | Step |
|---|---|
| Step 2 | Accept the elevation prompt; reboot after enabling Hyper-V; sign in again so Hyper-V Administrators membership applies |
| Before step 2 | Keep the age identity and the root password off the machine |
| Step 8 | Environment `cache-writer`: set deployment branches to the default branch only, then rotate the writer password ([limits-and-gaps.md](limits-and-gaps.md), security gaps, first row) |
| Before any runner (Phase 5) | Set fork pull-request approval to all external contributors ([next-phases.md](next-phases.md), entry gate 1) |

## Not yet proven

- "A reader who was not part of the work rebuilds from the runbook alone" (the Phase 8 clause) has not been tested.
- Steps 6 to 9 were built on one host in one session each; the weekly timer has fired once, not over weeks.
- Nothing here creates a runner; that starts in [next-phases.md](next-phases.md).
