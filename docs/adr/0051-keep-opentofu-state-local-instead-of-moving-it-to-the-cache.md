# 0051. Keep OpenTofu state local instead of moving it to the cache

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D79 in docs/platform/requirements.md
- Supersedes: the migration step of ADR 0013 (decision log D41)

## Context

ADR 0013 kept state local and encrypted "until the cache service exists", then planned a move to "the Phase 4 S3 backend" with `use_lockfile`. The cache service now exists (ADR 0048) and is not an S3 store: bazel-remote speaks HTTP for build artifacts and gRPC (switched off), with no bucket API, no conditional writes and no locking.

The cache is also the one service that untrusted runners reach (ADR 0050): they read it anonymously from the runner vnet.

## Options considered

1. Add an S3 store beside the cache and move state to it — a second service to run for one file, and still on the cache vnet.
2. Store state in the cache — not possible (no S3 API), and a shared boundary would put state next to runner-reachable data.
3. Keep the local encrypted backend of ADR 0013 and drop the migration.

## Decision

Option 3. State stays in WSL on the ext4 filesystem under `scripts/iac/tofu.sh`, encrypted with `enforced = true`, with the pre-apply copy to the Windows profile. ADR 0013 stays in force; only its migration step is withdrawn.

## Rationale and trade-offs

- State holds provider credentials and generated values. It must not share a trust boundary with a service that untrusted runners can reach, even when encrypted.
- Named partial, unchanged from ADR 0013: "remote state" is not met; locking is the local file lock and there is one operator on one workstation.
- Revisit if a second operator or a CI apply appears: that needs a backend with locking outside the runner vnet, decided in its own ADR.
