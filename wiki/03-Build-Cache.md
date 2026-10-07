# 03. Build Cache

A `bazel-remote` service in its own container serves content-addressed dependency and build-output caches to CI runners over one firewall path. The object-store cache of the previous host was retired, not ported (ADR 0020).

## Design

| Item | Value | Decision |
|---|---|---|
| Service | `bazel-remote` 2.6.2, pinned by sha256, uncompressed storage, size limit 8 GiB with LRU eviction | ADR 0048 |
| Placement | Container `cache01` (VMID 9050) at `10.99.17.10:8080` on vnet `cache`, routed through `pve01`; a hypervisor service would serve untrusted runners | ADR 0045 |
| Network path | One group-level firewall rule: the first line of `guest-egress` accepts tcp to the cache address and port; the container carries the group `cache-ingress` and nothing else | ADR 0046 |
| Reads and writes | Anonymous reads; writes need one writer credential held only in the GitHub environment `cache-writer` and used by save steps of default-branch push jobs | ADR 0050 |
| Integrity | The server verifies a CAS body against its digest on upload; the client verifies the digest again before extraction; a start-time sweep quarantines any stored blob whose content does not match its name | ADR 0048, row 65 |
| OpenTofu state | Stays local and encrypted; the cache is not an S3 store | ADR 0051 |

## Keys and stale binaries

| Cache | Key | Restore rule | Decision |
|---|---|---|---|
| Dependencies (`nuget`, `node_modules`) | sha256 over runner class, OS, architecture, toolchain version and every lockfile's sha256 | On a key hit | ADR 0049 |
| Build outputs (`dotnet-outputs`) | The same plus the git tree ids of the inputs, the configuration and the workspace root | Only on an exact match; never a "latest" archive | ADR 0049 |

A stale-binary test builds the solution at three commits and checks that outputs restore on the saved tree and miss on a changed tree. On hosted CI it reproduces the stale class on an old-style variant (`STALE detected`) and prints `FRESH`, `HIT up-to-date` and `PASS` for the new design (row 64, cache CI run 37592628530).

## Client

`scripts/ci/build_cache/` is layered as domain, application and adapters; a test fails when an inner layer imports an outer one (`tests/cache/test_dependency_rule.py`). The composite action `.github/actions/build-cache` calls it with `restore` or `save` and a kind. Restore reports `hit`, `miss` (no pointer, no store configured, store unreachable), `rejected` (digest or size mismatch, unsafe archive; the build runs cold) or `error`; save reports `saved`, `skipped`, `refused` or `failed`. No status fails a job. Unsetting `CACHE_URL` in `reusable-sdet-pipeline.yml` turns every restore into an immediate miss.

Extraction is bounded: only the plan's paths, capped bytes and members, and an interpreter that carries the tarfile-filter fixes (row 70).

## Measured

| Result | Row |
|---|---|
| 20 fresh-workspace runs on a runner-template clone with an unchanged lockfile: run 1 (writer) missed and saved; runs 2 to 20 hit every restore, dependencies 38/38 and outputs 19/19; the server access log agrees (`GET /ac` 200 x57, 404 x3) | 63 |
| API: anonymous GET 404 then 200, anonymous PUT 401, wrong password 401, writer PUT 200, a PUT with a wrong digest 500 and nothing stored, DELETE 401 | 62 |
| Corrupted blob rejected by the client and repaired by a writer re-save; service stopped means a miss and the build continues; two concurrent writers both succeed; eviction removes the oldest unread blobs | 65 |
| After a `pve01` reboot the container ran at 45 s and the service at 49 s with its data and every restore kind hitting | 67 |
| R15 with the cache path: runner clones 19/19 negatives, 2/2 positives; cache container 12/12, 1/1; unchanged after a `pve01` reboot | 66 |

## Limits

- Prometheus does not count action-cache lookups while AC validation is disabled; hits are counted from the access log (row 63).
- `bazel-remote` 2.6.2 serves a partially written file after `kill -9` during an upload; the start-time sweep covers it (row 65).
- Restricting environment `cache-writer` to the default branch is an owner setting on the repository; until it is set, the writer credential is protected only by the workflow condition.
- CI runs on hosted runners today (ADR 0054), which run with the cache disabled by design (row 68). The cache is used once self-hosted runners exist (Phase 5).

Procedures: `RUNBOOK.md` section 12.
