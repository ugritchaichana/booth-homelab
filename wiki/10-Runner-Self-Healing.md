# 10. Runner Self-Healing

Status: UNVERIFIED. The code is statically checked only; nothing has run on the live host.

## 1. Problem

- A runner CT with a full rootfs fails jobs (`No space left on device`; CT 103 rootfs is 12 GB).
- Proxmox is a Hyper-V VM on the Windows homelab PC. A PC or VM restart left every CT stopped, because no CT had `onboot`.
- Nothing restarted a dead runner service.

## 2. Pieces

| Piece | Where it runs | What it does |
|---|---|---|
| `scripts/runner-maintenance/job-started-hook.sh` | Runner CT, as the runner user, before every job (`ACTIONS_RUNNER_HOOK_JOB_STARTED`) | Prunes caches when free space is low; fails the job only if the disk is still below the hard floor |
| `scripts/runner-maintenance/disk-guard.sh` + `homelab-disk-guard.timer` | Runner CT, as root, daily and 5 min after boot | Runs the hook as the runner user, then vacuums the journal, cleans apt, prunes `/tmp`, and prunes docker when space is low |
| `scripts/runner-maintenance/runner-restart.conf` | Runner CT systemd drop-in for each `actions.runner.*.service` | `Restart=always`, `RestartSec=30` |
| `scripts/proxmox/watchdog/homelab-runner-watchdog.*` | PVE host, root, every 5 min | Starts stopped CTs; restarts a runner CT's service when none is active |
| `scripts/proxmox/install-runner-maintenance.sh` | PVE host, owner-run | Installs all of the above, sets `onboot` on existing CTs |
| `scripts/hyperv/ensure-proxmox-autostart.ps1` | Windows PC, owner-run, Admin PowerShell | Reports or sets the auto-start policy of the `Proxmox-Lab` VM |
| `--onboot 1`, `start_on_boot` | Provisioners and OpenTofu modules | New CTs boot with the host: MinIO (CT 104) first, then runners |

Runner service unit names are never hard-coded: every script globs `actions.runner.*.service`.

## 3. Thresholds

Environment variables, same names for the hook and the guard (the guard reads `/etc/default/homelab-disk-guard`).

| Variable | Default | Meaning |
|---|---|---|
| `HOMELAB_PRUNE_BELOW_GIB` | 3 | Prune when free space on the runner work filesystem is below this |
| `HOMELAB_HARD_FLOOR_GIB` | 1 | After pruning, fail the job (hook) or log a warning (guard) if still below this |
| `HOMELAB_TEMP_AGE_MIN` | 60 | `_work/_temp` entries younger than this are kept |
| `HOMELAB_ACTIONS_AGE_MIN` | 30 | `_work/_actions` entries younger than this are kept |
| `HOMELAB_RUNNER_DIR` | `$HOME/actions-runner` | Runner directory |

Hook prune order, re-measuring after each step and stopping once above the threshold: `_work/_temp`, `_work/_actions`, `_diag/*.log` older than 7 days, `~/.npm/_cacache`, NuGet caches, `/tmp` files owned by the runner older than 2 days.

The hook never touches `_work/<repo>/<repo>`: the pipeline reuses that checkout between jobs (`clean: false`).

Host watchdog: `WATCHDOG_CTS` (default `102 103 104`) in `/etc/default/homelab-runner-watchdog`. CTs whose `homelab-ephemeral-runner@<CT>.service` is enabled are skipped.

## 4. Install

1. On the Windows PC, Admin PowerShell: `.\scripts\hyperv\ensure-proxmox-autostart.ps1` (report), then with `-Apply`.
2. On the PVE host as root, from a checkout of the repo: `bash scripts/proxmox/install-runner-maintenance.sh --dry-run`, then without `--dry-run`.
3. Ephemeral mode: run the installer BEFORE `pct snapshot <CT> clean`, so the hook is part of the snapshot.

The installer defers a runner service restart while a job is running (`--restart-busy` overrides). The hook takes effect on the next runner start.

Ansible alternative: `iac/ansible/roles/runner_dotnet`, `runner_angular` and `proxmox_host` carry the same files; they copy from `scripts/runner-maintenance` and `scripts/proxmox/watchdog`, so there is one source.

## 5. Uninstall

Per runner CT (example CT 103):

```
pct exec 103 -- systemctl disable --now homelab-disk-guard.timer
pct exec 103 -- sed -i '/^ACTIONS_RUNNER_HOOK_JOB_STARTED=/d' /home/runner/actions-runner/.env
pct exec 103 -- sh -c 'rm -f /etc/systemd/system/actions.runner.*.service.d/restart.conf /etc/systemd/system/homelab-disk-guard.service /etc/systemd/system/homelab-disk-guard.timer /opt/homelab/*.sh /opt/homelab/runner-restart.conf'
pct exec 103 -- systemctl daemon-reload
pct exec 103 -- sh -c "systemctl list-unit-files 'actions.runner.*.service' --no-legend | awk '{print \$1}' | xargs -r systemctl restart"
```

On the PVE host:

```
systemctl disable --now homelab-runner-watchdog.timer
rm -f /usr/local/sbin/homelab-runner-watchdog.sh /etc/systemd/system/homelab-runner-watchdog.service /etc/systemd/system/homelab-runner-watchdog.timer /etc/default/homelab-runner-watchdog
systemctl daemon-reload
pct set 103 --delete onboot
```

Windows PC: `Set-VM -Name Proxmox-Lab -AutomaticStartAction Nothing`.

## 6. Verify

- Watchdog restarts a stopped runner: `pct exec 102 -- sh -c 'systemctl stop actions.runner.*.service'`, then within 5 minutes `journalctl -u homelab-runner-watchdog.service -n 20` shows `restarted` and the runner returns online on GitHub.
- Watchdog starts a stopped CT: `pct stop 103`; within 5 minutes it is `running` again.
- Timers: `pct exec 103 -- systemctl list-timers homelab-disk-guard.timer` and `systemctl list-timers homelab-runner-watchdog.timer`.
- Reboot test: restart the `Proxmox-Lab` VM; all CTs return and the runners show online.
- Hook output: the "Set up job" step of the next workflow run prints `homelab-hook:` lines with `free=` before and after each step.
- Boot order: `pct config 104 | grep -E 'onboot|startup'`.

## 7. Freeing CT 103 today is a separate owner step

The scripts prevent recurrence; they do not rescue a disk that is already full, and `pct push` fails on a full rootfs.

```
pct exec 103 -- df -h /
pct exec 103 -- du -xh --max-depth=2 /home/runner
```

Prune the large items found (never `_work/booth-homelab/booth-homelab`), or grow the rootfs: `pct resize 103 rootfs +8G`. Then run the installer.

## 8. Notes

- Intentional maintenance: the watchdog restarts a CT you stop on purpose. Run `systemctl stop homelab-runner-watchdog.timer` first, or edit `WATCHDOG_CTS`.
- `Restart=always` does not undo a manual `systemctl stop`; only the watchdog does.
- Hyper-V may not support `AutomaticStopAction Save` for a VM with nested virtualization; the script warns, and `-StopAction ShutDown` is the alternative.
- Auto-start covers a PC boot, not a PC that is asleep or powered off.
