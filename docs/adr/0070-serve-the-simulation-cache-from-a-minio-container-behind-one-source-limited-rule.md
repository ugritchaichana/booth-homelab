# 0070. Serve the simulation cache from a MinIO container behind one source-limited rule

- Status: Accepted; the store choice is superseded by 0072 (the firewall path and the container shape stand)
- Date: 2026-10-21
- Deciders: owner
- Decision log: D103 in docs/platform/requirements.md
- Builds on: ADR 0045, ADR 0046, ADR 0050

## Context

A CI simulation needs one object store that lab trial guests and hosted runners both reach, holding per-project build outputs written by default-branch jobs and read by every job. The owner chose MinIO on 2026-10-21 and asked for the pattern of the build cache: one scoped firewall path (ADR 0046), a credential split (ADR 0050).

- The build cache keeps bazel-remote and rejects MinIO because it is archived and source-only (D76, ADR 0048). That still holds for the build cache; this decision adds a second store and leaves the first unchanged.
- The guard requires every group of a vnet on every guest of that vnet and stops any guest with another enabled rule (`iac/ansible/roles/pve_firewall/files/guest-firewall-guard.py:73`, `:87`, `:95`). A third group on the `cache` vnet would stop the build cache container.
- The guests subnet is `10.99.16.0/24`; the five trial guests sit at host 100 plus their slot, `.107` to `.111` (`iac/tofu/stacks/guest/guests.yml`, `iac/tofu/stacks/guest/locals.tf`).

## Options considered

1. A new vnet and a new ingress group for the store: needs SDN, API-token grant, guard policy and SSH-config changes, and the store still receives every guest's traffic on its own port.
2. Add the store's port to `cache-ingress`: widens the existing build cache container's ingress.
3. The store beside the build cache on vnet `cache`, serving the cache port, carrying the same two groups, with one added `OUT` line limited by source.

## Decision

Option 3.

- Container `sim-cache`, VMID 9051, `10.99.17.11`, unprivileged, groups `guest-egress` and `cache-ingress` only (`iac/tofu/stacks/sim-cache`). The guard policy is unchanged and its existing cases cover this shape (`tests/isolation/test-guest-fw-guard.sh`: a compliant cache guest, an extra out rule, a missing group).
- One added line in `guest-egress`: `OUT ACCEPT -source +dc/sim-runners -dest 10.99.17.11 -p tcp -dport 8080`, rendered from `sim_cache_endpoint` and `sim_cache_sources` in `iac/inventory/hosts.yml`. The set `sim-runners` holds the five trial guests; a test derives the expected members from `guests.yml`. The port is the cache port: the endpoint has no port of its own, so `cache-ingress` admits it unchanged.
- MinIO serves S3 only. Console on `127.0.0.1:9001` with the browser off. One bucket, anonymous access none, two users: `sim-read` (get, list) and `sim-write` (put, denied under `_control/`). Root credentials stay in the container's environment file. Every request goes to an audit log (ADR 0071).
- Secrets are SOPS values read by the role, written through stdin and `no_log`; the units hold none.

## Rationale and trade-offs

- Reachable surface grows by one tcp port on one address, from five source addresses. A non-trial guest's packets match no accept and fall to the drop. A guest cannot add its own rule: the guard stops it.
- The ingress side is not narrowed: `cache-ingress` admits the whole guests subnet on the cache port, for both containers. Narrowing is at the source's egress only. HYPOTHESIS until the host proof: the firewall honours `-source` on an `OUT` rule inside a group; a rejected line fails `pve-firewall compile` and the dead-man restores the old file (`RUNBOOK.md` 2.11, check c).
- Changing the cache port moves both stores. Plain HTTP on the lab path; the tailnet leg is encrypted (ADR 0071).
- Proof offline: `tests/isolation/test-sim-cache-firewall.sh` (template and policy-snippet mutations), `tests/isolation/test-sim-cache-role.sh` (unit, task, policy and tripwire mutations), `iac/tofu/stacks/sim-cache/tests/sim-cache.tftest.hcl`.

## Consequences

- Open before apply, owner decision: upstream MinIO is archived (`gh api repos/minio/minio`: `archived: true`, read 2026-10-21), `dl.min.io` answers 410 Gone, and the newest tag with binaries is `RELEASE.2025-09-07T16-13-09Z`; the newest tag, `RELEASE.2025-10-15T17-29-55Z`, has no assets. Advisory CVE-2026-41145 (high: a caller that knows only a valid access key name writes objects without the secret) and advisory CVE-2026-40344 (high: unauthenticated object write through snowball auto-extract) list `>= RELEASE.2023-05-18T00-05-36Z` as vulnerable and `>= RELEASE.2026-04-11T03-20-12Z` as patched, a version the upstream tags do not carry (`gh api repos/minio/minio/security-advisories`, read 2026-10-21). The pinned binary is inside the vulnerable range. The write boundary of ADR 0050 does not hold against it and the tripwire does not see the attack, because the request names a known key. Choose a patched source (a maintained fork, a build from patched source, or another store), pin it by sha256 in `iac/ansible/roles/sim_cache_service/defaults/main.yml`, then apply.
- The role pins `minio`, `mc` and tailscale by sha256, each digest computed from the downloaded file and matched against the publisher's file.
