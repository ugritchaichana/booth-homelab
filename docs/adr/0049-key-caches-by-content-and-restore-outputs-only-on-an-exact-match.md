# 0049. Key caches by content and restore outputs only on an exact match

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D77 in docs/platform/requirements.md

## Context

The current build cache (`scripts/ci/cache-restore.sh`, `cache-save.sh`) restores `latest.tar.zst` for the branch, falls back to `master`, `main` and a global copy, touches the restored `*.dll`, `*.cache` and `project.assets.json` files to the current second, and bumps the files changed between `HEAD~1` and `HEAD` five seconds into the future. Row 17 of the evaluation measured the benefit: "the current build cache saves about 1 s (4630 → 3616 ms)". Row 18 is cited by the Phase 4 plan; its figure is not reproduced here because it was not supplied with this change.

The suspected defect: after a push of several commits, a source changed in an earlier commit of the push keeps its checkout time, which is older than the touched outputs, so MSBuild skips it and ships a stale binary. Neither NuGet nor npm had a lockfile, so no dependency cache could be keyed by content either.

## Options considered

1. Keep the branch-scoped `latest` archive and fix the timestamp bump — the bump can only name files it knows changed, and any fallback key restores outputs built from other inputs.
2. Use `actions/cache` — hosted-only, and the cache server is a separate Phase 4 decision.
3. A small client with ports, keyed by content: a dependency key from lockfile hashes, an output key from git tree ids, exact match only.

## Decision

Option 3: the Python package `scripts/ci/build_cache/` (standard library only), layered `domain` (keys and policy), `application` (restore and save use cases and the `Store` and `Archiver` ports) and `adapters` (filesystem store, tar archiver, environment probes). A dependency rule test (AST) fails when `domain` imports `application` or `adapters`, or `application` imports `adapters`.

- Dependency key (`nuget`, `node_modules`): sha256 over a canonical sorted record of namespace, runner class, OS id and version, architecture, toolchain version (`dotnet --version`, `node --version`) and the sha256 of every lockfile sorted by path.
- Output key (`dotnet-outputs`): sha256 over runner class, OS, architecture, SDK version, build configuration and the git tree id of every input path (`apps/backend`, `apps/fixtures`; the test project copies a file from `apps/fixtures`). Inputs that differ from `HEAD` (a dirty tree) make the key underivable, which is a miss.
- Outputs are restored only on an exact key match. There is no `latest`, no branch fallback and no restore key; the restore use case asks the store for one pointer and nothing else.
- Pointer and blob: a key maps to a small manifest (key, kind, blob sha256, size, compression); the manifest names a content-addressed blob. Restore verifies the blob sha256 and size against the manifest before extracting. A mismatch, a dangling pointer, a pointer for another key or an archive the extractor refuses is a rejected restore, counted and logged, and the build continues cold. A store that is unreachable or times out is a miss, never a job failure.
- Extraction uses `tarfile` with `filter="data"`; every member is checked first, absolute names are refused outright, so a bad archive extracts nothing. Compression is `zstd` when the binary exists, else gzip, recorded in the manifest. Archives are deterministic (sorted members, fixed owner and time), so two savers of the same inputs produce the same blob.
- Writes are allowed only when a writer credential is present and the event is a push to the default branch. Reads are always allowed. An existing key is never overwritten.
- On a hit for outputs the client sets every extracted file to one identical timestamp, taken after extraction. This is valid only because the key proves identical inputs.
- Lockfiles: `RestorePackagesWithLockFile` in `apps/backend/Directory.Build.props` with one `packages.lock.json` per project, generated with SDK 8.0.425, and `apps/frontend/package-lock.json`.

## Measured

- CONFIRMED, lockfiles: `dotnet restore --locked-mode` passes with SDK 8.0.425 and with SDK 10.0.100, and a plain restore with SDK 10 leaves all seven lockfiles byte-identical, so no `global.json` was added. `npm ci --ignore-scripts` succeeds from the generated lockfile (362 packages).
- CONFIRMED, stale-binary test (`tests/cache/test_stale_binaries.sh`, SDK 8.0.425 on Linux, three commits: a probe class added to `Core.Domain`, then a trivial change in `Billing.Api`, fresh checkout of the last one in the same workspace path): the old algorithm printed `OLD: not stale`. The suspected defect did not reproduce. Cause: the old script touches `*.dll`, `*.cache` and `project.assets.json` but not `*.pdb`; the restored `.pdb` keeps the time of the build that made it, `CoreCompile` lists it as an output, and MSBuild logged `Input file "Money.cs" is newer than output file "obj/Release/net8.0/Core.Domain.pdb"` and recompiled. The old cache is correct by accident and recompiles, which also fits the row 17 figure of about 1 s saved.
- CONFIRMED, new client: on the changed tree the restore is a miss and the build contains the probe (`NEW: FRESH`); after saving, a fresh checkout restores as a hit and `CoreCompile` is skipped in 7 of 7 projects with the probe present (`NEW: HIT up-to-date`).
- CONFIRMED, workspace path: outputs embed absolute paths (`project.assets.json`, the generated editorconfig). Restored into a different directory, every project recompiled. The key does not include the workspace path, so such a hit is correct but gains nothing; runners use a fixed workspace path.

## Rationale and trade-offs

- The point of the exact key is that a hit means the inputs are identical, which makes "treat the outputs as up to date" a fact instead of a guess. The old approach had to guess which files changed.
- HYPOTHESIS: the old algorithm becomes stale on a configuration without `.pdb` files (`DebugType` none) or where the restored `.pdb` is newer than the sources; not measured.
- Because a hit is only on an exact key, the hit ratio of outputs is low on pull requests (a new tree per push) and high on re-runs and on the default branch after a merge. The report subcommand prints the ratio so the value is measured, not assumed.
- Blobs are held in memory during restore and save, which suits the sizes seen here (about 5.7 MB of outputs). A streaming port is the change if a dependency archive outgrows runner memory.
- A pointer whose blob was lost stays rejected until the store is repaired, because an existing key is never overwritten.
- The Python floor is 3.11.4 (`tarfile` extraction filters).
- The hosted workflow `cache-ci.yml` proves the client, the lockfiles and the stale-binary test without the lab.
