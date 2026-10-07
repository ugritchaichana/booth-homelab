# 0048. Serve the build cache with bazel-remote

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D76 in docs/platform/requirements.md

## Context

Runners on the guest vnet need a shared build cache that survives a host reboot, evicts old entries by size so the disk cannot fill, and does not trust the client. The cache holds build output of public repositories and is reachable from untrusted runners (ADR 0050). The previous plan named an S3 store; ADR 0051 explains why state does not move there.

## Options considered

Facts read on 2026-10-07.

| Option | Finding |
|---|---|
| MinIO community | The repository README opens with "THIS REPOSITORY IS NO LONGER MAINTAINED" and points to commercial editions (https://github.com/minio/minio, README.md). Source-only, no fixes. |
| Garage | S3-compatible object store without a size-based eviction (LRU) setting; a full disk would need an external janitor. |
| SeaweedFS | Same finding: no size-based LRU; volume growth is the operator's problem. |
| nginx WebDAV plus a janitor | The `ngx_http_dav_module` page lists no content-digest check and no eviction (https://nginx.org/en/docs/http/ngx_http_dav_module.html), so both would be our own code. |
| bazel-remote v2.6.2 | Apache-2.0 (LICENSE at the tag). One static binary with a disk cache, LRU by `--max_size` (GiB, required), and Prometheus metrics. |

bazel-remote facts, source lines at tag v2.6.2 (https://github.com/buchgr/bazel-remote):

- A PUT to the content-addressed store verifies the sha256 of the body in both storage modes: `cache/disk/disk.go:369-380`, `cache/disk/casblob/casblob.go:564-579`.
- With `--allow_unauthenticated_reads`, GET and HEAD pass without credentials and every other method needs Basic auth: `main.go:486-500`.
- `--disable_http_ac_validation` (`main.go:250`) lets `/ac/<key>` hold arbitrary small manifests, which is how a non-Bazel client stores a cache index.
- `--grpc_address none` switches the gRPC listener off (README flag list, `main.go:208`).
- Metrics: `bazel_remote_incoming_requests_total{method,kind,status}` with `status=hit|miss` (`cache/disk/options.go:97`) and `bazel_remote_disk_cache_size_bytes`, `bazel_remote_disk_cache_size_bytes_limit`, `bazel_remote_disk_cache_evicted_bytes_total` (`cache/disk/lru.go:110-134`).
- The project publishes no checksum file; the pinned sha256 is the digest GitHub shows for the release asset.

## Decision

Run bazel-remote v2.6.2 (linux-amd64 release asset, sha256 `62e236bf8396e69396928e0d0c32062fbd5575f20fe55dc10a82eb791297e1a0`) in an unprivileged container on the cache vnet (`iac/tofu/stacks/cache-service`), configured by the role `cache_service`.

- Flags: `--dir`, `--max_size 8`, `--storage_mode uncompressed`, `--http_address` on the cache address, `--grpc_address none`, `--htpasswd_file`, `--allow_unauthenticated_reads`, `--disable_http_ac_validation`, `--max_blob_size` 2 GiB, `--enable_endpoint_metrics`.
- The 10 GiB data volume holds at most 8 GiB of cache: the limit must stay within 80 percent of the volume (a stack precondition reads both numbers).
- The binary is downloaded with `get_url` and a sha256 `checksum`, so a changed asset fails the converge.

## Rationale and trade-offs

- Server-side digest verification means a poisoned PUT with a wrong hash is refused even from the one credential holder; a client cannot plant content under another content's address.
- `uncompressed` storage trades disk for CPU on a 1-core container; the data is mostly already compressed archives.
- Accepted loss: the AC namespace has no validation (`--disable_http_ac_validation`), so a writer can store any small value under any AC key. Only the writer credential can do that (ADR 0050).
- Accepted loss: one binary pinned by hash, upgraded by editing the version and digest; no package manager tracks it.
- Cache entries are not backed up; a lost volume costs a cold cache, not data.
- HYPOTHESIS, settled by the host proof: that the systemd sandbox options (`ProtectSystem=strict`, `PrivateTmp`, `ProtectHome`) work inside an unprivileged container.
