# 03. Enterprise MinIO S3 Remote Cache (CT 104 Alpine LXC)

## 1. Overview & Upstream Deployment

Container **CT 104 (`minio-s3`)** serves as our distributed S3-compatible remote cache. It runs on **Alpine Linux 3.23 Standard**, giving it an ultra-lightweight memory footprint of **under 50 MB RAM**.

### Upstream Packaging Decision (Empirical Fact)
- Upstream URLs (`dl.min.io`) return `HTTP 410 Gone` for direct binary downloads following license updates.
- **Solution:** MinIO is deployed directly from official Alpine Linux packages:
  ```sh
  apk add minio minio-client minio-openrc
  rc-update add minio default
  service minio start
  ```

---

## 2. Service Endpoints & Bucket Topology

- **S3 API Endpoint:** `http://10.99.20.20:9000`
- **Web Console Endpoint:** `http://10.99.20.20:9001` (forwardable via SSH or web proxy)
- **Local Access Alias on CT 102:**
  ```bash
  mc alias set minio http://10.99.20.20:9000 minioadmin minioadmin
  ```

### Storage Buckets & Lifecycle Management (ILM)
| Bucket Name | Purpose | Retention Policy | Compression |
| :--- | :--- | :--- | :--- |
| `build-cache` | Stores `.nuget/packages/` and MSBuild `bin/obj/` archives | 7 Days (`mc ilm add --expiry-days 7`) | Zstd Level 3 |
| `test-artifacts` | Stores `.trx` test report XMLs and coverage metrics | 7 Days (`mc ilm add --expiry-days 7`) | Raw / Zip |

The 7-day retention policy ensures that homelab virtual disk storage is never exhausted by stale PR build archives.

---

## 3. High-Throughput Virtual Bus Benchmarks

Because CT 102 (`gha-runner-01`) and CT 104 (`minio-s3`) reside on the same internal Linux bridge (`vmbr1`), data transfer bypasses physical network cards and flows through Linux kernel memory buffers:

- **Benchmark Payload:** 71.68 MiB (Single Zstd archive containing complete build dependencies)
- **Transfer Time:** **110 milliseconds**
- **Effective Transfer Throughput:** **836.59 MiB/s**
- **Decompression Time (Zstd -T0):** **987 milliseconds**

```
Transfer Speed Comparison:
GitHub Actions Cloud Cache:  ~30 - 50 MB/s (Internet dependent)
AWS S3 over WAN:            ~40 - 80 MB/s
Homelab MinIO Virtual Bus:  836.59 MB/s (10x - 20x faster)
```

---

## 4. Cache Hardening & Isolation (CREEP Mitigation)

To eliminate cache injection and poisoning attacks across pull requests (CVE-2025-36852 / CREEP vulnerability), the cache hierarchy enforces branch isolation:

```
minio/build-cache/
├── branches/
│   ├── master/
│   │   └── build-cache-21b0a1d.tar.zst   <-- Authoritative baseline cache
│   ├── feature-pr-1-billing/
│   │   └── build-cache-9517eb7.tar.zst   <-- PR-scoped cache
│   └── feature-pr-2-order/
│       └── build-cache-90980d8.tar.zst   <-- PR-scoped cache
```

- Pull requests can read from `master`'s cache.
- Pull requests write only to their own branch prefix.
- Only merged code into `master` can update the authoritative `master` cache.
