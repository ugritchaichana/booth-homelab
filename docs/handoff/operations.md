# Operations (day 2)

Roles: operator (runs commands from the operator toolchain), root on pve01 (through `sudo` as the automation user), repository administrator (GitHub settings). Procedures and commands are in the [runbook](../../RUNBOOK.md), section 3; this page says what to do when, and what is not covered.

All lab machines stay running as evidence (decision D86, lab machines after the release); the on-demand VM stop of D21 (VM start policy) is suspended.

## Standing timers

| Timer | Period | Does |
|---|---|---|
| `homelab-template-weekly.timer` | weekly, persistent (catches up after downtime) | Rebuilds both template classes (ADR 0041) |
| `homelab-guest-firewall-guard.timer` | every minute, and one minute after boot | Stops a guest that violates the per-vnet policy (ADR 0047); output and actions in runbook 3.6 |
| Host converge | manual | Applies pending upstream updates and may reboot the host |

Nothing alerts on a failed run of either timer yet ([limits-and-gaps.md](limits-and-gaps.md)).

## Templates

Runbook 3.3 "Golden templates" holds every command. Build times: [results.md](results.md).

| Task | Notes |
|---|---|
| Rebuild now | Start `homelab-template-build@<class>.service`, not the bare command: the unit writes the failure marker |
| See state | `homelab-template status`: exit 0 only when each class has exactly one `current`; `current-count=0` or `2` means consumers refuse that class |
| Roll back for everyone | `homelab-template rollback <class>` as root; run again to swap back; the next build promotes on top of the rolled-back version |
| Hold one consumer on a version | Set `template_pins` for that consumer's stack; the pinned version must still exist, because retention keeps only `current` and `previous` |
| Recover a failed build | The runbook table maps the last `FAILED` or `REFUSED` journal line to an action; leftover guests are destroyed by the next build |
| Bump a base image, a toolchain or the runner | Edit the pins, converge, rebuild; an artifact without its hash pin is refused by `tests/isolation/test-template-content.sh` (ADR 0042) |

A build refuses when the thin pool or `local` storage is above its threshold; the numbers are unmeasured placeholders ([limits-and-gaps.md](limits-and-gaps.md)). Deleting a volume needs a privilege no token holds, so removing a downloaded base image needs one operator `pvesm free` per file (row 48, token boundary).

## Cache

Runbook 3.4 "Cache: health, purge, rotation" holds every command. The service is the container `build-cache-debian-13`, reached as `ssh -F ~/.config/homelab/ssh_config build-cache`.

| Task | Notes |
|---|---|
| Health | `systemctl status bazel-remote`; the journal shows `wait-for-address`, `verify-cas` and `Loaded N existing disk cache items` |
| Metrics | `/metrics` has the size, evicted bytes and the size limit; the action-cache hit counter stays 0 while AC validation is off, so count hits from the access log (200 hit, 404 miss; [metrics-after-loop.txt](../evidence/phase4/metrics-after-loop.txt)) |
| Size and eviction | Budget 8 GiB on a 10 GiB volume, LRU by size; measured on a 1 GiB instance: 40 x 32 MiB written, 32 kept, the 8 oldest unread evicted ([cache-eviction.txt](../evidence/phase4/cache-eviction.txt)) |
| Purge (cold cache) | Stop the service, delete the data directory contents, start it; builds run cold until a default-branch save repopulates |
| Switch the cache off | Empty `CACHE_URL` in the reusable pipeline; every restore answers "miss: no store configured". Hosted runners already run this way |
| After a crash or reboot | Nothing manual: the unit waits for the address, then sweeps every blob and quarantines one whose content does not match its name |

Restore and save statuses never fail a job; read the job summary, not the job result, to see cache health.

## Secrets rotation

Commands: runbook 3.5. Every secret file has one writer ([secrets README](../../iac/secrets/README.md)).

| Secret | Evidence level |
|---|---|
| Cache writer password | Rotated on the host 2026-10-08, after the environment branch policy was set: converge changed=2, then changed=0 ([rotate-converge-1.txt](../evidence/closeout/rotate-converge-1.txt), [rotate-converge-2.txt](../evidence/closeout/rotate-converge-2.txt)); script also tested offline with mutants (`tests/isolation/test-cache-writer-secret.sh`). Hyper-V checkpoints older than the rotation still hold the old value (runbook 3.1) |
| Provisioner API token | Implemented (`pve_api_identity_rotate`); no host run recorded |
| OpenTofu state passphrase | Implemented; no host run recorded |
| R15 probe key | Exercised in the Phase 4 re-creations of the probe guests ([real-host-defects.md](../knowledge/real-host-defects.md)) |
| Root password and SSH keys | No run recorded |
| Age identity | Rule documented; no drill |
| GitHub fine-grained tokens | Created in Phase 5; do not exist yet |

A rotation never run on the host is a hypothesis, not a procedure: schedule a drill of each in Phase 7.

## Guests from a flavor

`scripts/iac/new-guest.sh` creates a guest of a cloud flavor in one command (runbook 2.10; [ADR 0055](../adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md)); a worked example with output is in [examples.md](examples.md). Add a flavor by adding an entry to `iac/tofu/flavors.json` (cores, memory, disk, balloon); every guest of that flavor changes size at its next apply. The two demo guests on `pve01` are `demo-lxc-runner-v6` (VMID 9501) and `demo-vm-docker-v7` (VMID 9502), both `aws/t3.medium`.

## Adding a host

1. Add an entry to `iac/inventory/hosts.yml` (address, management source, guest and cache networks, cache endpoint); an example is in [examples.md](examples.md). The OpenTofu stacks select the entry by `var.host`; no code changes (ADR 0021; `iac/tofu/stacks/proxmox-host/tests/two_hosts.tftest.hcl`).
2. Create `iac/secrets/hosts/<name>-ssh.sops.yaml` with the host's public key, then render the SSH config; the render fails without that file ([secrets README](../../iac/secrets/README.md)).
3. Install PVE (or any Linux host the roles support), run the bootstrap play as root once, then `site.yml` as the automation user.
4. Apply the host stack with `var.host=<name>`, then rebuild templates and re-run the R15 probe on that host.
5. If the host is a Hyper-V guest, give it its own `.psd1` for the Windows scripts; otherwise skip `hyperv_guest`.

Evidence level: a second host was planned (two-host fixture test) and never applied. The first real second host is the test of this procedure.

## Restore points

- The PVE VM: `Invoke-PveVm.ps1 -Action Checkpoint`, only while the VM is Off, with a free-space floor and a polled read-back; restore plus start reaches SSH in about 16 s (row 45, checkpoint action; ADR 0019). A checkpoint of a running nested VM is not used.
- Templates: two versions per class and one-command rollback.
- OpenTofu state: encrypted, on WSL storage, with an encrypted copy on the Windows side after each apply.
- Backups to another device with a timed restore do not exist (Phase 7).

## Converge reboots

Runbook 3.2. `site.yml` applies upstream updates and reboots pve01 when the running kernel is not the boot default (D40, package repository switch and upgrade). Once runners exist, drain the pool first or converge in a maintenance window; this is a Phase 5 entry gate ([next-phases.md](next-phases.md)). A laptop that enters Modern Standby suspends the VM and can invalidate a long run (row 43, converge run): keep the workstation on AC power, where no sleep was measured (row 10, power settings).

## The guard

Behaviour, output table and actions: runbook 3.6. When the guard cannot read its policy or list guests it exits 4 and stops nothing ("the guard is blind"); nothing alerts on that ([limits-and-gaps.md](limits-and-gaps.md)). After adding a vnet or a group, update the inventory so the policy file is re-rendered, or every guest on the new vnet is a violation (ADR 0047).
