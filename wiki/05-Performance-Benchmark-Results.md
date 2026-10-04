# 05. Performance & Optimization Tuning Benchmark Results

## 1. Benchmark Overview & Methodology

To validate the real-world performance gains of the Proxmox self-hosted CI pipeline and MinIO S3 remote cache, a 3-stage validation suite was executed:
1. **Master Baseline (Cold Run):** Full clean build, package restore, and initial cache population.
2. **PR #1 (`Billing.Api` modified):** Cache restore from base, affected testing on `Billing.Api` only.
3. **PR #2 (`Order.Api` modified):** Cache restore, partial incremental recompile of `Order.Api`, affected testing on `Order.Api` only, and cache update.

---

## 2. Telemetry Comparison Matrix

| Metric | Cold Baseline (Master) | PR #1 (Billing Touch) | PR #2 (Order Touch) | Master Push (Merge #2) |
| :--- | :--- | :--- | :--- | :--- |
| **GHA Run URL** | [#37225068243](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225068243) | [#37225258263](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225258263) | [#37225396301](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225396301) | [#37225932588](https://github.com/ugritchaichana/booth-homelab/actions/runs/37225932588) |
| **Trigger Event** | Push (`master`) | Pull Request (`#1`) | Pull Request (`#2`) | Push (`master`) |
| **Cache Hit Status** | MISS (Cold) | **HIT (Base `master`)** | **HIT (Base `master`)** | **HIT (`master`)** |
| **Cache Download Duration** | N/A | **110 ms** | **128 ms** | **120 ms** |
| **Cache Throughput** | N/A | **836.59 MiB/s** | **780+ MiB/s** | **800+ MiB/s** |
| **Cache Size** | 71.68 MiB (Zstd) | 71.68 MiB (Zstd) | 71.68 MiB (Zstd) | 71.68 MiB (Zstd) |
| **Build Duration** | 4,630 ms (Full) | 4,028 ms | 3,616 ms (Incremental) | 4,123 ms |
| **Test Execution Duration** | Full suite (3,100 ms) | **Billing Tests (1,850 ms)** | **Order Tests (1,720 ms)** | No code touch (12 ms) |
| **Suites Skipped** | 0% | **Order (100% Skipped)** | **Billing (100% Skipped)** | 100% Skipped |
| **Cache Save Duration** | 1,400 ms | Skipped (Read-only) | **1,615 ms** | Skipped |
| **Total Pipeline Time** | **45 seconds** | **23 seconds** | **28 seconds** | **24 seconds** |

---

## 3. Key Observations & Performance Gains

### 1. Zero External Network Dependency
Because all dependencies (`.nuget/packages/` and MSBuild assets) are stored inside CT 104 MinIO on Proxmox, pipelines are immune to internet jitter, NuGet rate limits, or external CDN degradation.

### 2. Virtual Bus Throughput
Transferring 71.68 MiB across `vmbr1` took only **110 milliseconds** at **836.59 MiB/s**. Compared to typical GitHub Actions cloud caching (which averages 30–50 MB/s over the public internet), the local virtual bus delivers a **~16x throughput multiplier**.

### 3. Impact of Affected Test Resolution
In PR #1, `Order.Api.UnitTests` was skipped completely. In PR #2, `Billing.Api.UnitTests` was skipped completely. In a monorepo with 50+ microservices, this strategy keeps test duration bounded strictly to the blast radius of the commit rather than growing with total repository size.

---

## 4. Parallel Dual-Runner Architecture Benchmark (CT 102 + CT 103)

| Component | Target Runner | Environment Specs | Cold Run Duration | Warm Cache Target |
| :--- | :--- | :--- | :--- | :--- |
| **Backend (.NET 8 Build & Cache)** | `pve-runner-01` (CT 102) | 3 vCPUs, 4GB RAM, Docker-in-LXC | **16 seconds** | ~3.6 - 4.1s |
| **Backend (.NET Unit + Integration Tests)** | `pve-runner-01` (CT 102) | Debian 12, .NET 8.0.425 | **16 seconds** (6/6 tests pass) | ~1.7 - 2.1s (Affected) |
| **Frontend (Angular Jest Suite)** | `pve-runner-angular` (CT 103) | 2 vCPUs, 1.5GB RAM, Node 20 LTS | **103s** (npm seed + upload) | **~4.2 seconds** (MinIO hit) |
| **Cache Storage (MinIO S3)** | `minio-s3` (CT 104) | Debian 12, MinIO S3 Server | **28 MiB (npm)** / **73 MiB (.NET)** | **>800 MiB/s Virtual Bus** |

### Concurrent Execution Timeline (Run [#37233575350](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350))
- **CT 102 & CT 103 Parallel Firing:** Stage 2 (.NET) and Stage 5 (Angular Jest) trigger simultaneously.
- **Frontend Headless Efficiency:** Pure jsdom + Jest executes 4 test suites (19 test cases) in **4.229 s** without spawning Chromium browsers, maintaining an ultra-lean memory footprint on CT 103.
- **Cache Seeding:** `node_modules.tar.zst` (28 MiB) is now populated in `minio/build-cache/npm/`, unlocking instant sub-second downloads for subsequent frontend runs.
