# Results

Everything below was measured on one workstation (a reference implementation). Numbers carry their requirements row and raw file; a number without a source is not a result. The measured rows are section 3 of [requirements.md](../platform/requirements.md); hashes of each raw file are in the phase indexes ([1](../evidence/phase1/INDEX.md), [2](../evidence/phase2/INDEX.md), [3](../evidence/phase3/INDEX.md), [4](../evidence/phase4/INDEX.md)).

## Baselines and targets

| Item | Value | Source |
|---|---|---|
| Hosted runners, full suite, cold cache | 71 s: Telemetry 5 s, Build 19 s, Test .NET 29 s, Angular 35 s, Report 3 s; queue 5 s or less | row 15 (hosted baseline), [run 37355482969](https://github.com/ugritchaichana/booth-homelab/actions/runs/37355482969) |
| Previous self-hosted runners | 174 s; the Report job queued 64 s because the `dotnet` label had one runner | row 16 (old self-hosted baseline), [run 37341728563](https://github.com/ugritchaichana/booth-homelab/actions/runs/37341728563) attempt 2 |
| Old build cache saving | About 1 s (4630 ms to 3616 ms) | row 17 (old cache saving), jobs 111502928303 and 111503888437 |
| Targets, each to hold for 5 consecutive runs | Full suite 60 s or less with warm caches; queue-to-start p95 10 s or less; scale-from-zero to job start 30 s or less; cache hit ratio 95% or more on an unchanged lockfile | requirements.md section 4, question 7 |

No run on the new platform exists for the first three targets: no runner of the new platform has run a job, so the suite time, the queue time and the scale-from-zero time are unmeasured (requirements.md section 8, status `not measured`). Do not read the cache numbers below as a suite time.

## Build cache (Phase 4)

| Result | Value | Source |
|---|---|---|
| Hit ratio, unchanged lockfile, 20 fresh-workspace runs on a runner-template clone (4 cores, 4 GiB) | Run 1 (writer context) missed 3 times and saved 3 entries; runs 2-20 hit every restore: dependencies 38/38, outputs 19/19 | row 63 (hit ratio over 20 runs); [cache-loop20-results.txt](../evidence/phase4/cache-loop20-results.txt) |
| Same window by the server | `GET /ac` 200 x57 and 404 x3; `GET /cas` 200 x57 | row 63 (hit ratio over 20 runs); [cache-accesslog-loop20.txt](../evidence/phase4/cache-accesslog-loop20.txt) |
| Per run | Dependency restore 6.2-7.5 s, install 1.1-2.0 s, output restore 0.4-0.6 s, build 1.0-1.6 s with `CoreCompile` skipped | row 63 (hit ratio over 20 runs) |
| API contract | Anonymous GET 404 then 200, anonymous PUT 401, wrong password 401, writer PUT 200, digest mismatch 500 with nothing stored, DELETE 401, size limit 8 GiB | row 62 (cache API); [cache-api.txt](../evidence/phase4/cache-api.txt) |
| Stale binaries | The old script as shipped was not stale (the program database time forces recompilation); the defect class reproduces once all outputs are touched and the commit id is left out; the new design is fresh and a hit skips `CoreCompile` 7 of 7 | row 64, run 37592628530 |
| Corrupt blob, service down, restart, concurrent writers, eviction | Corrupt blob rejected by digest and repaired by a re-save; service stopped: miss in 2003 ms and the build continues; restart reloads 7 items and hits; two concurrent writers both succeed; 40 x 32 MiB into 1 GiB keeps 32 and evicts the 8 oldest unread | row 65 (cache edge cases); [cache-edges-1.txt](../evidence/phase4/cache-edges-1.txt), [cache-edges-2.txt](../evidence/phase4/cache-edges-2.txt), [cache-eviction.txt](../evidence/phase4/cache-eviction.txt) |
| Crash finding | bazel-remote 2.6.2 served a partially written file with 200 after `kill -9`; the start-time sweep quarantines it (404 afterwards) | row 65 (cache edge cases); [cache-kill9-check.txt](../evidence/phase4/cache-kill9-check.txt), [after sweep](../evidence/phase4/cache-kill9-after-sweep.txt) |
| Service hardening | `systemd-analyze security` exposure 2.1 OK | row 70 (security hardening); [cache-sandbox.txt](../evidence/phase4/cache-sandbox.txt) |
| Hosted fallback with the cache disabled | Every job green, save jobs skipped outside a default-branch push, 0 `store unreachable` lines | row 68, run 37602620111 |

### Cache effect on one run

Measured on a runner-template clone with an unchanged lockfile: run 1 is cold (it also saves), runs 2 to 20 are warm. A run is the sum of dependency restore, install, output restore and build; save time is excluded. Source: [cache-loop20-results.txt](../evidence/phase4/cache-loop20-results.txt).

| Part | Cold run 1 | Warm median, runs 2-20 | Change |
|---|---|---|---|
| Whole run | 12.9 s | 9.8 s | about 24% faster |
| Build output (output restore plus build) | 5.2 s | 1.6 s | 68% faster |
| Dependencies (restore plus install) | 7.8 s | 8.2 s | 6% slower |

Only one cold run exists, so read the percentages as indicative. The dependency part does not improve because restoring about 100 MB costs about as much as a network install for this small app. CI on GitHub-hosted runners does not use the cache yet ([ADR 0054](../adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md)).

## Templates (Phase 3)

| Result | Value | Source |
|---|---|---|
| Build time per version | `lxc-runner` about 2 min 15 s; `vm-docker` about 3 min 5 s | row 55 (template build time); [build-weekly-1.txt](../evidence/phase3/build-weekly-1.txt), [timer-fired builds](../evidence/phase3/journal-timer-fired.txt) |
| Retention and rollback | After six builds each class holds two versions (current v6, previous v5); rollback moved `current` back and forward, exit 0, on both classes; each manifest hashes to the value in its template description | row 56 (retention and rollback); [build-lxc-retention.txt](../evidence/phase3/build-lxc-retention.txt), [evidence-rollback-vm.txt](../evidence/phase3/evidence-rollback-vm.txt) |
| Weekly timer | Fired the rebuild of both classes | row 56 (retention and rollback); [journal-timer-fired.txt](../evidence/phase3/journal-timer-fired.txt) |
| Storage after Phase 3 and after Phase 4 | Thin pool data 20.06% (four template volumes); 24.29% after the cache volumes | row 56, requirements.md section 7.2b |
| VM-class clone | `docker run hello-world` works; no `svm` or `vmx`; no Docker TCP listener; runner user without sudo (but see the cloud-init finding) | row 59 (clone isolation); [evidence-vm-clone.txt](../evidence/phase3/evidence-vm-clone.txt) |
| Defects found only on the host | Listed in [real-host-defects.md](../knowledge/real-host-defects.md), one table per phase | row 55 (first host builds) |

## Isolation (R15)

| Result | Value | Source |
|---|---|---|
| Host-side layer measured from PVE, before any runner | Guest to host (445, 135, 139), home router, host addresses and mesh DNS dropped, each paired with Windows reaching the same target; HTTPS and DNS to a public resolver work | row 38 (host-side isolation layer); [j8-results.md](../evidence/phase1/j8-results.md) |
| After the host reboot | 18 ACLs read back; spoofed MAC drops traffic; ACLs removed for 14.8 s and restored to 18; Windows rule disabled for 10.6 s, ACLs alone still block guest to host 445 | row 42 (ACLs after a reboot); [r15-after-reboot-results.md](../evidence/phase1/r15-after-reboot-results.md) |
| Red first | With the PVE firewall stopped the gateway and management rows are open and every external row is still dropped by the Windows layer; port isolation holds without the firewall | row 51 (red-first isolation) |
| Phase 2 end state, per guest, in four phases (baseline, container reboot, PVE reboot, laptop reboot) | `negatives_blocked=15/15 positives_ok=1/1 egress_curl=200` each time | row 52 (per-guest isolation runs) |
| Template clones | `15/15 1/1 egress_curl=200` on the container and the VM | row 59 (clone isolation); [r15-baseline-lxc.txt](../evidence/phase3/r15-baseline-lxc.txt), [vm](../evidence/phase3/r15-baseline-vm.txt) |
| With the cache path | Runners `19/19 2/2`, cache container `12/12 1/1`; red-first runners `10/10 11/11`, cache `8/8 5/5`; after a pve01 reboot runners `19/19 2/2`, cache `12/12 1/1` | row 66 (R15 with the cache path); [baseline](../evidence/phase4/r15-baseline-lxc.txt), [red-first](../evidence/phase4/r15-red-first-lxc.txt), [after reboot](../evidence/phase4/r15-after-pve-reboot-lxc.txt) |
| Not measured in any phase | A VPN peer's web service; a host inside the harvested prefixes | row 38 (host-side isolation layer), row 42 (ACLs after a reboot), row 52 (per-guest isolation runs) |

## Host, reboots and cold starts

All starts below are of the PVE VM or its guests, not of a runner; scale-from-zero for a runner is unmeasured.

| Result | Value | Source |
|---|---|---|
| Unattended install | 459 s, powered itself off; first cold start: TCP 22 answered 18.1 s after `Start-VM` | row 35 (unattended install); [New-PveHost log](../evidence/phase1/New-PveHost-20261006-155339.log) |
| Restore point | Checkpoint restore plus start reaches SSH in 15.7-16 s (four measurements); disk chain 17.7 GiB with 3 checkpoints | row 45 (checkpoint action) |
| After a laptop reboot | SSH 15.8 s after start; WSL 1.8 s; Docker `hello-world` exit 0; 12449 MB RAM free with the VM and Docker running | row 53 (laptop reboot); [phase1-carryover-after-host-reboot.txt](../evidence/phase2/phase1-carryover-after-host-reboot.txt) |
| After a pve01 reboot | SSH 43 s; cache container running at 45 s; service at 49 s with data and every restore kind hitting | row 67 (reboot timings); [pve-reboot.txt](../evidence/phase4/pve-reboot.txt) |
| Regression gate with the VM running | WSL boots in 2.3 s; available RAM never below 6049 MB; C: 163.9 GB free | row 40 (regression gate); [j9-gate.md](../evidence/phase1/j9-gate.md) |
| Converge | Run 1 from the fresh install `ok=8 changed=5` in 254 s including the reboot into the new kernel; a later run `ok=114 changed=0` | row 43 (converge run) and row 46 (first converge) |
| IaC state | Plan exits 0 after apply; state mode 600 with `encrypted_data` only; concurrent plan refused by the lock; wrong passphrase fails | row 49 (OpenTofu state); [tofu-reds.txt](../evidence/phase2/tofu-reds.txt) |
| CI | IaC CI green at the head of every phase 2 chain pull request (run ids in row 54, IaC CI runs); catalog tests run 37560039041; evidence checks 37597435239 and 37600851460 | row 54 (IaC CI runs), row 60 (idempotence held), row 69 (evidence published) |

## Reading these results honestly

- Row 63 (hit ratio over 20 runs) measures a clone driven from pve01 with an unchanged lockfile and a fresh workspace per run, the same template, firewall and route as a runner (ADR 0053). It is not a real runner and not a real workflow run; Phase 5's load test owes a real hit-ratio run.
- The reference VM was sized for a laptop (12 vCPU, 20 GiB); absolute build and restore times do not transfer to other hardware, only the method does.
- Where a number has no raw file, it is not cited here.
