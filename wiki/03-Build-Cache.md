# 03. Build Cache

A `bazel-remote` service in its own container serves content-addressed dependency and build-output caches to CI runners over one firewall path. Measured results: [docs/handoff/results.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/results.md).

## Design

| Item | Value | Decision |
|---|---|---|
| Service | `bazel-remote` 2.6.2, pinned by sha256, uncompressed storage, size limit 8 GiB with LRU eviction | ADR 0048 |
| Placement | Container `build-cache-debian-13` (inventory alias `build-cache`, VMID 9050) at `10.99.17.10:8080` on vnet `cache`, routed through `pve01`; a hypervisor service would serve untrusted runners | ADR 0045 |
| Network path | One group-level firewall rule: the first line of `guest-egress` accepts tcp to the cache address and port; the container carries the group `cache-ingress` and nothing else | ADR 0046 |
| Reads and writes | Anonymous reads; writes need one writer credential held only in the GitHub environment `cache-writer` and used by save steps of default-branch push jobs | ADR 0050 |
| Integrity | The server verifies a CAS body against its digest on upload; the client verifies the digest again before extraction; a start-time sweep quarantines any stored blob whose content does not match its name | ADR 0048 |
| OpenTofu state | Stays local and encrypted; the cache is not an S3 store | ADR 0051 |

## Keys

| Cache | Key | Restore rule | Decision |
|---|---|---|---|
| Dependencies (`nuget`, `node_modules`) | sha256 over runner class, OS, architecture, toolchain version and every lockfile's sha256 | On a key hit | ADR 0049 |
| Build outputs (`dotnet-outputs`) | The same plus the git tree ids of the inputs, the configuration and the workspace root | Only on an exact match; never a "latest" archive | ADR 0049 |

A stale-binary test builds the solution at three commits and checks that outputs restore on the saved tree and miss on a changed tree (`tests/cache/test_stale_binaries.sh`, run by `cache-ci.yml`).

## Client

`scripts/ci/build_cache/` is layered as domain, application and adapters; `tests/cache/test_dependency_rule.py` fails when an inner layer imports an outer one. The composite action `.github/actions/build-cache` calls it with `restore` or `save` and a kind. Restore reports `hit`, `miss` (no pointer, no store configured, store unreachable), `rejected` (digest or size mismatch, unsafe archive; the build runs cold) or `error`; save reports `saved`, `skipped`, `refused` or `failed`. No status fails a job. Unsetting `CACHE_URL` in `reusable-sdet-pipeline.yml` turns every restore into an immediate miss.

Extraction is bounded: only the plan's paths, capped bytes and members, and an interpreter that carries the tarfile-filter fixes.

## Limits

- Open gaps, including the `bazel-remote` behavior after `kill -9`: [docs/handoff/limits-and-gaps.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/limits-and-gaps.md). The action-cache counters that stay at zero: [docs/knowledge/real-host-defects.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/knowledge/real-host-defects.md).
- CI runs on hosted runners today (ADR 0054), which run with the cache disabled by design; the cache is used once self-hosted runners exist.

Procedures: [RUNBOOK.md](https://github.com/ugritchaichana/booth-homelab/blob/master/RUNBOOK.md), "Day-2 operations", "Cache: health, purge, rotation".
