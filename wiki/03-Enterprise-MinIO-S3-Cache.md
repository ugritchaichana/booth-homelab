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
- **Runner Access Alias on CT 102 / CT 103 (reader account only):**
  ```bash
  mc alias set minio http://10.99.20.20:9000 "$SDET_PR_READER_USER" "$SDET_PR_READER_PASS"
  ```

### Storage Buckets & Lifecycle Management (ILM)
| Bucket Name | Purpose | Retention Policy | Compression |
| :--- | :--- | :--- | :--- |
| `build-cache` | Stores `.nuget/packages/` and MSBuild `bin/obj/` archives | 7 Days (`mc ilm add --expiry-days 7`) | Zstd Level 3 |
| `test-artifacts` | Stores `.trx` test report XMLs and coverage metrics | 7 Days (`mc ilm add --expiry-days 7`) | Raw / Zip |

The 7-day retention policy ensures that homelab virtual disk storage is never exhausted by stale PR build archives.

### Access Policy: Read-Only PR Access & Authenticated Master Write
- **Read-Only PR Access:** S3 cache buckets require authenticated access via scoped `sdet_pr_reader` credentials, allowing pull requests to restore dependencies without permission to write or poison cache keys.
- **Strictly Authenticated Write/Edit:** Modifying, overwriting, or deleting objects (`s3:PutObject`, `s3:DeleteObject`) strictly requires authenticated writer credentials (`sdet_ci_writer`). Only verified builds on `master`/`main` can write, with SHA256 integrity digest verification before extraction.

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

- Pull requests operate with scoped read-only credentials (`sdet_pr_reader`) and cannot write or mutate cache keys.
- Only authoritative CI runs on `master`/`main` possess write permissions (`sdet_ci_writer`).
- All restored archives verify a writer-computed SHA256 integrity digest prior to workspace decompression.

---

## 5. Enterprise Credential Hardening & Password Standards

> [!WARNING]
> **No Credentials Ship With This Repository:**  
> The MinIO root, IAM reader and IAM writer credentials are supplied only through environment variables (`MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `SDET_PR_READER_PASS`, `SDET_CI_WRITER_PASS`); the provisioning scripts and the Ansible role stop when one is missing.  
> **Any credential that was ever committed to this repository's history must be treated as exposed and rotated.**

### Credential Rotation SOP
To update root credentials on the Alpine MinIO container (`CT 104`):
```bash
# 1. Update MinIO environment file on CT 104
pct exec 104 -- sh -c "cat <<EOF > /etc/conf.d/minio
MINIO_VOLUMES=\"/var/lib/minio/data\"
MINIO_OPTS=\"--address :9000 --console-address :9001\"
MINIO_ROOT_USER=\"<new-root-user>\"
MINIO_ROOT_PASSWORD=\"<new-root-password>\"
EOF"

# 2. Restart MinIO service daemon
pct exec 104 -- rc-service minio restart

# 3. Runners hold only the reader alias, so a root rotation needs no runner change.
#    Rotate the reader/writer accounts by re-running scripts/proxmox/configure_iam_cache_accounts.py.
```

### Scoped IAM Service Accounts (Least Privilege)
Avoid sharing the administrative root credentials across automated CI jobs:
```bash
# Provision read-only service account for PR cache restoration
pct exec 102 -- mc admin user add minio sdet_pr_reader StrongPrReaderP@ss123!
pct exec 102 -- mc admin policy attach minio readonly --user sdet_pr_reader

# Provision read-write service account for master release builds
pct exec 102 -- mc admin user add minio sdet_ci_writer StrongCiWriterP@ss456!
pct exec 102 -- mc admin policy attach minio readwrite --user sdet_ci_writer
```

### Password Complexity Baseline (NIST SP 800-63B / CIS)
- **Minimum Length:** $\ge 20$ characters for root admin; $\ge 32$ characters for automated API tokens.
- **Character Classes:** Mixed uppercase (`A-Z`), lowercase (`a-z`), decimal digits (`0-9`), and special symbols (`!@#$%^&*()-_+=[{]}|:;,.<>?~`).
- **Forbidden Elements:** Dictionary words, sequential numbers, repetitive patterns, or host/homelab identifiers.
- **Storage & Injection:** Store credentials in encrypted secret vaults (GitHub Secrets / HashiCorp Vault), never committed to git in plaintext.
