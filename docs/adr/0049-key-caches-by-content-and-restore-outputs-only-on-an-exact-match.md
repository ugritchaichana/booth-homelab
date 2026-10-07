# 0049. Key caches by content and restore outputs only on an exact match

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D77 in docs/platform/requirements.md

## Context

The current build cache (`scripts/ci/cache-restore.sh`, `cache-save.sh`) restores `latest.tar.zst` for the branch, falls back to `master`, `main` and a global copy, touches the restored `*.dll`, `*.cache` and `project.assets.json` files to the current second, and bumps the files changed between `HEAD~1` and `HEAD` five seconds into the future. Two rows of the evaluation concern it:

- Row 17: "The current build cache saves about 1 s (4630 → 3616 ms)", measured on jobs 111502928303 and 111503888437.
- Row 18: "The restore bumps only files changed since `HEAD~1`, on top of `latest.tar.zst`, which records no SHA. A multi-commit push may therefore reuse stale binaries" — a HYPOTHESIS at `scripts/ci/cache-restore.sh:123-128`.

Neither NuGet nor npm had a lockfile, so no dependency cache could be keyed by content either.

## Options considered

1. Keep the branch-scoped `latest` archive and fix the timestamp bump — the bump can only name files it knows changed, and any fallback key restores outputs built from other inputs.
2. Use `actions/cache` — hosted-only, and the cache server is a separate Phase 4 decision.
3. A small client with ports, keyed by content: a dependency key from lockfile hashes, an output key from git tree ids, exact match only.

## Decision

Option 3: the Python package `scripts/ci/build_cache/` (standard library only), layered `domain` (keys and policy), `application` (restore and save use cases and the `Store` and `Archiver` ports) and `adapters` (filesystem store, tar archiver, environment probes). A dependency rule test (AST) fails when `domain` imports `application` or `adapters`, or `application` imports `adapters`.

- Dependency key (`nuget`, `node_modules`): sha256 over a canonical sorted record of namespace, runner class, OS id and version, architecture, toolchain version (`dotnet --version`, `node --version`) and the sha256 of every lockfile sorted by path.
- Output key (`dotnet-outputs`): sha256 over runner class, OS, architecture, SDK version, build configuration, the absolute workspace root and the git tree id of every input path (`apps/backend`, `apps/fixtures`; the test project copies a file from `apps/fixtures`). The root is in the key because outputs embed absolute paths, so a hit in another directory would restore bytes that MSBuild then recompiles. Dependency keys stay path-free. Inputs that differ from `HEAD` (a dirty tree) make the key underivable, which is a miss.
- Outputs are restored only on an exact key match. There is no `latest`, no branch fallback and no restore key; the restore use case asks the store for one pointer and nothing else.
- Pointer and blob: a key maps to a small manifest (key, kind, blob sha256, size, compression); the manifest names a content-addressed blob. Restore verifies the blob sha256 and size against the manifest before extracting. A digest or size mismatch, a pointer for another key or an archive the extractor refuses is a rejected restore, counted and logged, and the build continues cold. A pointer whose blob the store no longer holds (evicted on its own) is a miss. A store that is unreachable or times out is a miss, never a job failure.
- Extraction uses `tarfile` with `filter="data"`; every member is checked first, absolute names are refused outright, so a bad archive extracts nothing. Compression is `zstd` when the binary exists, else gzip, recorded in the manifest. Archives are deterministic (sorted members, fixed owner and time), so two savers of the same inputs produce the same blob.
- Writes are allowed only when a writer credential is present and the event is a push to the default branch. Reads are always allowed. A save is skipped only when this job's restore of the same key was a verified hit (read from the stats file or `--restore-status`); after any other restore result the save writes the blob and replaces the pointer, because an LRU store evicts pointers and blobs independently and a pointer alone proves nothing.
- On a hit for outputs the client sets every extracted file to one identical timestamp, taken after extraction. This is valid only because the key proves identical inputs.
- Lockfiles: `RestorePackagesWithLockFile` in `apps/backend/Directory.Build.props` with one `packages.lock.json` per project, generated with SDK 8.0.425, and `apps/frontend/package-lock.json`.

## Measured

- CONFIRMED, lockfiles: `dotnet restore --locked-mode` passes with SDK 8.0.425 and with SDK 10.0.100, and a plain restore with SDK 10 leaves all seven lockfiles byte-identical, so no `global.json` was added. `npm ci --ignore-scripts` succeeds from the generated lockfile (362 packages).
- Row 18, RULED OUT as shipped on SDK 8.0.425. `tests/cache/test_stale_binaries.sh` builds commit A, then commit B (a probe class added to `Core.Domain`) and commit C (a trivial change in `Billing.Api`), and restores A's outputs into a fresh checkout of C at the same workspace path, with the old restore algorithm copied verbatim from `cache-restore.sh:115-140`:
  - As shipped: `OLD-as-shipped: not stale (pdb mtime forces CoreCompile)`. The script touches `*.dll`, `*.cache` and `project.assets.json` but not `*.pdb`; `CoreCompile` lists the `.pdb` as an output, and MSBuild logged `Input file "Money.cs" is newer than output file "obj/Release/net8.0/Core.Domain.pdb"`. The old cache restored 5.7 MB of bytes and saved almost no compile time, which matches row 17.
  - With `*.pdb` also touched: `OLD+pdb: not stale`. The .NET SDK appends the commit id to the informational version, so the generated `AssemblyInfo.cs` is rewritten on every new commit and `CoreCompile` runs again.
  - With every file under `bin` and `obj` touched and `IncludeSourceRevisionInInformationalVersion=false`: `OLD+all-outputs-touched+no-revision-in-version: STALE detected`. The probe class was missing from `Core.Domain.dll`. The defect class of row 18 is real; it needs both holes closed, and neither is closed in this repository today. The same variant without the property was not stale when run once during development (not kept in the test), so the property is what separates them.
- CONFIRMED, new client: on the changed tree the restore is a miss and the build contains the probe (`NEW: FRESH`); after saving, a fresh checkout restores as a hit in 230 to 270 ms and `CoreCompile` is skipped in 7 of 7 projects with the probe present (`NEW: HIT up-to-date (CoreCompile skipped 7/7)`). The test passes only when the last variant of the old algorithm is stale, the new client is fresh and the hit is up to date, so the detector is shown able to fail.
- CONFIRMED, workspace path: outputs embed absolute paths (`project.assets.json`, the generated editorconfig). Restored into a different directory, every project recompiled; the workspace root is therefore part of the output key.
- CONFIRMED, same tree and a different commit: the commit id sits in `AssemblyInfo.cs`, so a hit on a tree reached by a new commit recompiles. A hit skips compilation only when the commit is the same.

## Rationale and trade-offs

- The point of the exact key is that a hit means the inputs are identical, which makes "treat the outputs as up to date" a fact instead of a guess. The old approach had to guess which files changed.
- The new design rules out the stale-binary class by construction (exact key over the input trees) and does not depend on the two accidents that protect the old one; it also skips `CoreCompile` on a hit, which the old cache did not do in the measured scenario.
- Because a hit is only on an exact key, the hit ratio of outputs is low on pull requests (a new tree per push) and high on re-runs and on the default branch after a merge. The report subcommand prints the ratio so the value is measured, not assumed.
- Blobs are held in memory during restore and save, which suits the sizes seen here (about 5.7 MB of outputs). A streaming port is the change if a dependency archive outgrows runner memory.
- Saving after a miss rewrites the blob and the pointer. Two jobs that miss the same key write the same bytes (the archive is deterministic) or two complete blobs with the last pointer winning; both are valid.
- The Python floor is 3.11.4 (`tarfile` extraction filters).
- The hosted workflow `cache-ci.yml` proves the client, the lockfiles and the stale-binary test without the lab.
