# Operations (day 2)

Roles: operator (runs commands from the operator toolchain), root on pve01 (through `sudo` as the automation user), repository administrator (GitHub settings). Procedures live in the [runbook](../../RUNBOOK.md), section 3 "Day-2 operations"; this page says what to do when, and what is not yet covered.

## Standing timers

| Timer | Period | Does | Evidence |
|---|---|---|---|
| `homelab-template-weekly.timer` | weekly, persistent (catches up after downtime) | Rebuilds both template classes | rows 56, 60; ADR 0041 |
| `homelab-guest-firewall-guard.timer` | every minute, also 1 minute after boot | Stops a guest that violates the per-vnet policy | row 70; ADR 0047 |
| Host converge | manual | Applies pending upstream updates and may reboot | see "Converge reboots" |

Nothing alerts on a failed run of either timer yet; see [limits-and-gaps.md](limits-and-gaps.md).

## Templates

| Task | How | Notes |
|---|---|---|
| Rebuild now | Start `homelab-template-build@<class>.service` on pve01 (runbook 3.3 "Golden templates", build) | Use the unit, not the bare command: the unit writes the failure marker. About 2 min 15 s for `lxc-runner` and 3 min 5 s for `vm-docker` per version on the reference host (row 55) |
| See state | `homelab-template status`: one line per class, exit 0 only when each class has exactly one `current` | `current-count=0` or `2` means consumers refuse that class (runbook 3.3, status) |
| Roll back for everyone | `homelab-template rollback <class>` as root; run again to swap back | The next build promotes on top of the rolled-back version (runbook 3.3, rollback and repair) |
| Hold one consumer on a version | Set `template_pins` for that consumer's stack | Survives new builds; the pinned version must still exist because retention keeps only `current` and `previous` (runbook 3.3, "Consume or pin a template") |
| Recover a failed build | Read the failure marker and the journal; the runbook table maps the last `FAILED` or `REFUSED` line to an action (runbook 3.3, "Recover a failed build") | Leftover guests are destroyed by the next build |
| Bump a base image | Change the sha512 pin of the class in the `pve_templates` role defaults, converge, rebuild (runbook 3.3, "Bump a base image pin") | Images are fetched by Ansible, never by a token (ADR 0041) |
| Bump a toolchain or the runner | Edit the class `versions.yml` with the new hashes, converge, rebuild (runbook 3.3, "Bump a pinned toolchain in `lxc-runner`" and "Bump the `vm-docker` class") | An artifact without its hash pin is refused by `tests/isolation/test-template-content.sh` (ADR 0042) |

A build refuses when the thin pool or `local` storage is above its threshold (defaults: data and metadata 70%, 8 GiB free on `local`). These numbers are placeholders in the role defaults, not measured limits; the reference pool sat at 20-24% (row 56; requirements.md section 7.2b).

Deleting a volume needs a privilege no token holds, so removing a downloaded base image needs one operator `pvesm free` per file (row 48).

## Cache

| Task | How | Notes |
|---|---|---|
| Health | On `cache01`: `systemctl status bazel-remote`; journal lines `wait-for-address`, `verify-cas` and `Loaded N existing disk cache items` | Runbook 3.4 "Cache: health, purge, rotation" |
| Metrics | `/metrics`: `bazel_remote_disk_cache_size_bytes`, `..._evicted_bytes_total`, the size limit | The action-cache hit counter stays 0 while AC validation is off; count hits from the access log (200 hit, 404 miss) (row 63, [metrics-after-loop.txt](../evidence/phase4/metrics-after-loop.txt)) |
| Size and eviction | Budget 8 GiB on a 10 GiB volume, LRU by size; measured on a 1 GiB instance: 40 x 32 MiB written, 32 kept, the 8 oldest unread evicted | row 65, [cache-eviction.txt](../evidence/phase4/cache-eviction.txt) |
| Purge (cold cache) | Stop the service, delete the data directory contents, start it | Builds run cold until a default-branch save repopulates; costs only time |
| Switch the cache off | Unset `CACHE_URL` in the reusable pipeline | Every restore answers "miss: no store configured" at once and builds run cold; the hosted fallback already runs this way (row 68) |
| Rotate the writer credential | `scripts/iac/cache-writer-secret.sh --rotate`, then converge `cache.yml` | Script tested offline (`tests/isolation/test-cache-writer-secret.sh`); other rotations: see "Secrets rotation" below |
| After a crash or reboot | Nothing manual: the unit waits for the address, then sweeps every blob and quarantines one whose content does not match its name | Measured: container at 45 s, service at 49 s after a pve01 reboot, data intact (row 67) |

Restore statuses (`hit`, `miss`, `rejected`, `error`, `saved`, `skipped`, `refused`, `failed`) never fail a job; read the job summary, not the job result, to see cache health (runbook 3.4, client wiring).

## Secrets rotation

The commands are in runbook 3.5 "Secrets rotation"; this table adds what evidence exists. Every secret file has one writer ([secrets README](../../iac/secrets/README.md)).

| Secret | Procedure (runbook 3.5) | Evidence level |
|---|---|---|
| Cache writer password | `scripts/iac/cache-writer-secret.sh --rotate`, then converge `cache.yml`; also rotate once after the environment branch policy is set (ADR 0050) | Script tested offline with mutants (`tests/isolation/test-cache-writer-secret.sh`); no host rotation run is recorded |
| Provisioner API token | `site.yml` with `-e pve_api_identity_rotate=true`; the role replaces the token and writes SOPS through stdin | Implemented (the variable exists in the role); no host run recorded |
| OpenTofu state passphrase | Move the encrypted state aside, `scripts/iac/tofu.sh <stack> <host> init-passphrase --rotate`, recreate or import the state | Implemented; no host run recorded |
| R15 probe key | Delete the key on the host, rerun the keygen tag, replace the VM clone | Exercised in the phase 4 re-creations of the probe guests (real-host defects list) |
| Root password and SSH keys | Edit the SOPS files, converge for keys; a new root password reaches the host only through a rebuilt ISO | No run recorded |
| Age identity | Change every value, not only the encryption: old commits stay decryptable; new recipient in `.sops.yaml` | Rule documented; no drill |
| GitHub fine-grained tokens | Created by the repository administrator in Phase 5 | Do not exist yet |

A rotation that was never run on the host is a hypothesis, not a procedure: schedule a drill of each in Phase 7 and record the outcome.

## Adding a host (R5.1)

1. Add an entry to `iac/inventory/hosts.yml` (address, management source, guest and cache networks, cache endpoint). The OpenTofu stacks select the entry by `var.host`; no code changes (ADR 0021; `iac/tofu/stacks/proxmox-host/tests/two_hosts.tftest.hcl`).
2. Create `iac/secrets/hosts/<name>-ssh.sops.yaml` with the host's public key, then render the SSH config; the render fails without that file ([secrets README](../../iac/secrets/README.md)).
3. Install PVE (or any Linux host the roles support), run the bootstrap play as root once, then `site.yml` as the automation user.
4. Apply the host stack with `var.host=<name>`, then rebuild templates and re-run the R15 probe on that host.
5. If the host is a Hyper-V guest, give it its own `.psd1` for the Windows scripts; otherwise skip `hyperv_guest`.

Evidence level: a second host was planned (two-host fixture test), never applied (R5 "passes when" reads "plan-only host"). The first real second host is the test of this procedure.

## Restore points

- The PVE VM (runbook 3.1 "The VM: start, stop, status, checkpoint"): `Invoke-PveVm.ps1 -Action Checkpoint`, only while the VM is Off, with a free-space floor and a polled read-back. Restore plus start measured at 15.7-16 s to SSH (rows 45, 53; ADR 0019). A checkpoint of a running nested VM is not used.
- Templates: two versions per class and one-command rollback (above).
- OpenTofu state: encrypted, on WSL storage, with an encrypted copy on the Windows side after each apply (D51).
- Backups to another device with a timed restore do not exist (Phase 7).

## Converge reboots

Runbook 3.2 "Converge and the reboot caveat". `site.yml` applies upstream updates and reboots pve01 when the running kernel is not the boot default (D40). It happened in the reference runs: the second Phase 4 converge moved the kernel and rebooted the host by design (row 61). Once runners exist, drain the pool first or converge in a maintenance window; this is a Phase 5 entry gate ([next-phases.md](next-phases.md)). Also, a laptop that enters Modern Standby suspends the VM and can invalidate a long run (row 43): keep the workstation on AC power, where no sleep was measured (row 10), or use a host that does not sleep.

## The guard

What it does: see [architecture.md](architecture.md). Procedure and output table: runbook 3.6 "The guest firewall guard". In short: `journalctl -u homelab-guest-firewall-guard.service -n 20` ends with an `ok, N guest(s) checked` line when all is well; a violation is a journal line with the VMID, type and reason (`VIOLATION vmid=... firewall not enabled` in row 47) and leaves a marker under `/var/lib/homelab/guest-firewall-guard/violations/<id>`. A guest stopped by the guard is not restarted by it; fix the guest's firewall, then start it. A line reporting a guest whose configuration cannot be read counts toward a limit of three runs before it is treated as a violation; a `STOP FAILED` line means stop the guest by hand now. After adding a vnet or a group, update the inventory so the policy file is re-rendered, or every guest on the new vnet is a violation (ADR 0047).

Known limit: when the guard cannot read its policy or list guests it exits 4 and stops nothing ("the guard is blind"); nothing alerts on that ([security-model.md](security-model.md)).
