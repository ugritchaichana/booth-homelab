# 0072. Replace MinIO with SeaweedFS for the simulation cache and front it with a tripwire proxy

- Status: Accepted
- Date: 2026-10-21
- Deciders: owner
- Decision log: D105 in docs/platform/requirements.md
- Supersedes: the store choice of ADR 0070 and the tripwire mechanism of ADR 0071

## Context

ADR 0070 chose MinIO and recorded that apply was blocked: upstream is archived, `dl.min.io` answers 410 Gone, and advisories CVE-2026-41145 and CVE-2026-40344 (high, unauthenticated object write) list the only downloadable binary as vulnerable with no patched release in the upstream tags (read 2026-10-21). The owner replaced MinIO with SeaweedFS, which keeps the S3 API the handover template needs.

Facts read 2026-10-21 (`gh api`, source at tag 4.48, commit `530be3e3`):

- SeaweedFS is not archived, pushed the same day, Apache-2.0. Release 4.48, published 2026-09-28.
- Integrity of the binary: the release ships `linux_amd64.tar.gz` and a `.md5` sidecar only. No sha256 file, no signature, and `gh attestation verify` answers 404. The pinned digest is the sha256 of the file I downloaded (`4a7d1083...1124`); its md5 `867076808db89e5e3800aa0a2120a7ae` matches the publisher's sidecar. Trust is first use plus a weak hash.
- Advisories: the repository lists 25 (9 critical, 12 high, 4 medium, published 2026-06-10 to 2026-09-23). 24 end at or below 4.45. One, GHSA-99q7-x53r-6j4g (filer TUS handler, `>= 4.39`, no patched version), covers 4.48; it needs filer JWT scoping, which is not configured, and the role turns the TUS path off (`-filer.tusBasePath=`) and binds the filer to loopback. The advisory database query for the Go module lists six, all patched at or below 4.34.
- Many of the 25 are unauthenticated internal interfaces (gRPC identity injection, volume server fetch, Raft). Every listener except the proxy is therefore bound to loopback.
- Request audit: the gateway's only audit hook is `-s3.auditLogConfig`, which sends events to a fluentd receiver (`weed/s3api/s3err/audit_fluent.go`) and records the identity name, not the access key. No receiver exists in the lab.
- Identity semantics (`weed/s3api/auth_credentials.go`, `Identity.CanDo`): actions only allow; `Read:<bucket>` matches one bucket; there is no deny. A request with no identity named `anonymous` gets `AccessDenied` (the anonymous branch of the auth switch). Delete shares the action `Write`.

## Options considered

1. SeaweedFS S3 behind its own identity file, audit through fluentd: a receiver to run and decode, and an event that omits the key.
2. SeaweedFS behind a local reverse proxy that reads the authorization header: one small program, sees every request before the store.
3. Keep MinIO from source or a fork: another unpatched or third-party binary.

## Decision

Option 2, with the S3 API of SeaweedFS 4.48 (`weed server`, binaries pinned by sha256).

- Same container, VMID 9051, address and cache port as ADR 0070. The proxy listens on the cache port; the store (master, volume, filer, S3 gateway) listens on loopback only, telemetry off, embedded IAM off, Iceberg and Lance listeners off.
- Two identities in a static `s3.json`: `sim-read` (Read and List) and `sim-write` (Write, Read, List), each on named buckets only, no `anonymous`. The identity names are public; their access key ids are random strings of at least 20 characters held in SOPS like the secret keys, because the repository is public and a literal id would let anyone reach the signature check. The proxy reads the permitted ids from a root-owned file, never from its command line, and logs the identity, not the id. Buckets: `sim-cache` and `sim-control`. Denying the writer under a prefix cannot be expressed, so the marker lives in a second bucket neither identity can write. The cost: `Write` also deletes and overwrites objects in `sim-cache`.
- The proxy (`iac/ansible/roles/sim_cache_service/files/tripwire.py`) refuses a request with no `Authorization` header, a credential in the query string, a non-v4 scheme or a key outside `sim-read` and `sim-write`; it writes a marker and answers `AccessDenied` without forwarding. It refuses a request with more than one `Authorization` header. It also marks a store reply of `InvalidAccessKeyId` or `SignatureDoesNotMatch`, and any 403 to a HEAD (the reply has no body to read, and neither identity is refused a HEAD inside its own buckets). It logs method, path, claimed key and status, never a signature.
- A path unit watches the marker directory; its root service stops the connector and publishes the marker through the loopback filer to `sim-control/tripwire`. The connector is bound to the proxy (`BindsTo=`, so it stops when the proxy exits for any reason, not only when the proxy is stopped) and refuses to start while the marker exists. The proxy unit has `Restart=no` and `OnFailure=` a oneshot that leaves the marker, so a crash or an out-of-memory kill counts as a trip and waits for the owner (ADR 0071, unchanged otherwise).

## Rationale and trade-offs

- Measured on the pinned binary on loopback (`SIM_CACHE_WEED_BIN` run of `tests/isolation/test-sim-cache-role.sh`): anonymous list, get and put answer 403 AccessDenied; the reader cannot put or delete; neither identity writes `sim-control`; an unknown key answers InvalidAccessKeyId and a wrong secret SignatureDoesNotMatch; the marker put through the filer is readable by both identities through S3.
- Each bucket is a volume collection and takes volume slots: with four slots the first bucket grew all of them and the filer could not store the marker for the second (measured). The unit gives 30 slots of 256 MB (7.5 GB on the 10 GB volume, the same 80 percent rule as the build cache); objects are chunked at 4 MB, so the volume size is not an object limit.
- A wrong secret with a known key trips only after the store's reply, so the request already reached the store. A stolen valid key pair is not detected.
- Fail closed: a stopped proxy stops the connector, and a restart of the proxy needs the connector started again. A tripped marker survives reboot.
- HYPOTHESIS until the host run: the path unit fires on the proxy's rename; userspace tailscale forwards to the proxy on loopback; the proxy's throughput on multi-hundred-megabyte uploads (measured only at 5 MiB).
- The publisher checksum is md5; if the owner wants a stronger root, build from the tag and pin the result.
