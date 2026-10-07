# 05. Measured Results

Every number on this page is backed by a row of `docs/platform/requirements.md` (section 3) or a run id; the row lists the raw evidence under `docs/evidence/<phase>/` (each phase has an `INDEX.md` with the sha256 of every file). Numbers measured on the retired host in earlier benchmark pages are not repeated here (ADR 0020).

## CI baselines

| Result | Value | Source |
|---|---|---|
| Hosted runners, full suite, cold cache | 71 s (telemetry 5 s, build 19 s, .NET test 29 s, Angular 35 s, report 3 s; queue 5 s or less) | row 15, run 37355482969 |
| Retired self-hosted host, full suite | 174 s; the report job queued 64 s because the `dotnet` label had one runner | row 16, run 37341728563 attempt 2 |

## Build cache

| Result | Value | Source |
|---|---|---|
| Hit ratio, unchanged lockfile, 20 fresh-workspace runs | runs 2 to 20 hit every restore: dependencies 38/38, outputs 19/19 | row 63 |
| Per run | dependency restore 6.2 to 7.5 s, install 1.1 to 2.0 s, output restore 0.4 to 0.6 s, build 1.0 to 1.6 s with `CoreCompile` skipped | row 63 |
| Stale-binary class | reproduced on an old-style variant, absent in the new design | row 64, cache CI run 37592628530 |
| Cold start after a `pve01` reboot | container at 45 s, service at 49 s, data intact | row 67 |
| Hosted fallback with the cache disabled | all jobs green | row 68, run 37602620111 |

## Golden templates

| Result | Value | Source |
|---|---|---|
| Build time on `pve01` | about 2 min 15 s (`lxc-runner`), about 3 min 5 s (`vm-docker`) | row 55; [build log](../docs/evidence/phase3/build-weekly-3.txt), [timer-fired builds](../docs/evidence/phase3/journal-timer-fired.txt) |
| Retention and rollback | two versions per class; rollback exit 0 on both classes | row 56 |
| Thin pool after six builds | 20.06% data, 2.01% metadata | row 56; [timer-fired builds](../docs/evidence/phase3/journal-timer-fired.txt) |

## Isolation (R15)

| Result | Value | Source |
|---|---|---|
| Hyper-V port ACLs read back | 18 rules, none outside the weight range | rows 35, 42, 53 |
| Runner clones, container and VM, with the firewall on | 15/15 negatives blocked, 1/1 positive; unchanged after a container reboot, a PVE reboot and a laptop reboot | rows 52, 59 |
| Runner clones with the cache path | 19/19 negatives, 2/2 positives; after a PVE reboot the same | row 66 |
| Cache container | 12/12 negatives, 1/1 positive | row 66 |
| Red first (node firewall stopped) | gateway and management ports open, proving the PVE layer blocks those rows | rows 51, 66 |

Two rows (a VPN peer's web service, a host in a harvested prefix) are `NOT MEASURED` in every phase because no positive control exists for them.

## Host and operations

| Result | Value | Source |
|---|---|---|
| Unattended PVE 9.1 install | 459 s; first cold start answered SSH 18.1 s after start | row 35 |
| Restore from a checkpoint | cold start answered SSH in 15.7 to 16 s | row 45 |
| Converge idempotence | second run `changed=0`; after the probe teardown `ok=114 changed=0` | rows 43, 46 |
| Workstation regression gate with the VM running | WSL boots in 2.3 s; Docker `hello-world` exits 0; available RAM never below 6049 MB | row 40 |

## Not measured yet

The platform targets need the runner pool (Phases 5 and 6): full suite 60 s or less with warm caches, queue-to-start p95 10 s or less, scale-from-zero to job start 30 s or less. Section 8 of the requirements keeps them as `not measured`.
