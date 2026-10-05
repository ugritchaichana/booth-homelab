# 05. Performance & Optimization Tuning Benchmark Results

## 1. Benchmark Overview & Methodology

To validate the real-world performance gains of the Proxmox self-hosted CI pipeline and MinIO S3 remote cache, a 3-stage validation suite was executed:
1. **Master Baseline (Cold Run):** Full clean build, package restore, and initial cache population.
2. **PR #1 (`Billing.Api` modified):** Cache restore from base, affected testing on `Billing.Api` only.
3. **PR #2 (`Order.Api` modified):** Cache restore, partial incremental recompile of `Order.Api`, affected testing on `Order.Api` only, and cache update.

---

## 2. Telemetry Comparison Matrix

Each row is one run. Every value is printed by the log of the linked job (`Downloaded in`, the `MiB/s` transfer table, `[BENCHMARK]` lines and `Total Cache Save Time`); `n/a` means the log prints no such value for that run.

| Run (job log) | Trigger Event | Cache Restore | Download Duration | Restore Throughput | Build Time | Affected Test Runner Time | Cache Save Time |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| [37225068243](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225068243/job/111502928303) | `push` to `master` | MISS | n/a | n/a | 4630 ms | 13 ms | 3058 ms |
| [37225258263](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225258263/job/111503480614) | `pull_request` | HIT | 100 ms | 941.39 MiB/s | 4182 ms | 2649 ms | 1756 ms |
| [37225396301](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225396301/job/111503888437) | `pull_request` | HIT | 128 ms | 708.19 MiB/s | 3616 ms | 3332 ms | 1615 ms |
| [37225932588](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225932588/job/111505458158) | `push` to `master` | HIT | 106 ms | 888.90 MiB/s | 4123 ms | 12 ms | 2450 ms |

Each restore and save transfer moved a 71.68 MiB archive (Zstd).

---

## 3. Key Observations & Performance Gains

### 1. Zero External Network Dependency
Dependencies (`.nuget/packages/` and MSBuild assets) are stored inside CT 104 MinIO on Proxmox, so a cache-hit restore does not fetch them from public registries.

### 2. Virtual Bus Throughput
Transferring 71.68 MiB across `vmbr1` took `Downloaded in 106 ms` at 888.90 MiB/s in [run 37225932588](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225932588/job/111505458158).

### 3. Impact of Affected Test Resolution
The log of [run 37225258263](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225258263/job/111503480614) lists a pass for `Billing.Api.UnitTests` only, and the log of [run 37225396301](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225396301/job/111503888437) lists a pass for `Order.Api.UnitTests` only. The strategy keeps test duration bounded to the blast radius of the commit rather than growing with total repository size.

---

## 4. Parallel Dual-Runner Architecture Benchmark (CT 102 + CT 103)

| Component | Target Runner | Environment Specs | First run ([37233575350](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350)) | Second run ([37235401356](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356)) |
| :--- | :--- | :--- | :--- | :--- |
| **Backend (.NET 8 Build)** | `pve-runner-01` (CT 102) | 3 vCPUs, 4GB RAM, Docker-in-LXC | `Build Time: 4252 ms` ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350/job/111528207387)) | `Build Time: 4707 ms` ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533415551)) |
| **Backend (.NET Affected Tests)** | `pve-runner-01` (CT 102) | Debian 12 | `Affected Test Runner Time: 13 ms` ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350/job/111528312574)) | `Affected Test Runner Time: 16 ms` ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533483063)) |
| **Frontend (Angular Jest Suite)** | `pve-runner-angular` (CT 103) | 2 vCPUs, 1.5GB RAM, Node 20 ([run 37347994171](https://github.com/ugritchaichana/booth-homelab/actions/runs/37347994171/job/111891371382) prints the `node20` cache-key prefix) | `Completed in: 103003 ms`, npm install after a cache miss ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350/job/111528154780)) | `Completed in: 3856 ms`, cache hit ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533373752)) |
| **Cache Storage (MinIO S3)** | `minio-s3` (CT 104) | Debian 12, MinIO S3 Server | `node_modules` archive 27.89 MiB at 220.86 MiB/s on save ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350/job/111528154780)) | `node_modules` archive 27.89 MiB at 824.29 MiB/s on restore ([job](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533373752)) |

### Concurrent Execution Timeline (Run [#37233575350](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350))
- **CT 102 & CT 103 Parallel Firing:** Stage 2 (.NET) and Stage 5 (Angular Jest) trigger simultaneously.
- **Frontend Headless Efficiency:** Pure jsdom + Jest executes 4 test suites (19 test cases) with Jest `Time: 4.229 s` ([job log](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350/job/111528154780)) without spawning Chromium browsers.
- **Cache Seeding:** `node_modules.tar.zst` (27.89 MiB) is populated in `minio/build-cache/npm/`; the second run restored it at 824.29 MiB/s ([job log](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533373752)).
