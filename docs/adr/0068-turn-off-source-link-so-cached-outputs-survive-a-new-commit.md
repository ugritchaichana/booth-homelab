# 0068. Turn off Source Link so cached outputs survive a new commit

- Status: Accepted
- Date: 2026-10-14
- Deciders: operator, under the owner's Phase 5 definition (D96)
- Decision log: D97 in docs/platform/requirements.md
- Amends: [0063](0063-cache-build-outputs-per-project-and-keep-the-commit-id-out-of-the-version.md) (the build flags)

## Context

ADR 0063 took the commit id out of the assembly version so that a cache hit on a new commit skips the compile step. The final Phase 5 load test ran on `master` after the merge, where a push had saved every project's outputs. Outputs restored as designed: 7 of 7 on a change outside every project and 4 of 7 on a `Billing.Api` change. The compile step was still not skipped: both cases ran CoreCompile in 7 of 7 projects, where 0 and 3 were expected (load test runs 38561057073, 38561053694 and 38561061292).

A diagnostic run printed MSBuild's reason for each project (run 38563298991, job 115849664424):

```
Building target "CoreCompile" completely.
Input file "obj/Release/net8.0/Core.Domain.sourcelink.json" is newer than output file "obj/Release/net8.0/Core.Domain.dll".
```

The .NET 8 SDK turns on Source Link by default. Source Link writes `<project>.sourcelink.json` into `obj` with the commit id in its URL, and that file is an input of CoreCompile. A new commit rewrites it after the restore, so it is newer than every restored assembly. This is the same channel as the version string, through a second file.

`tests/cache/test_stale_binaries.sh` did not catch it. The test clones its fixture from a local path, and Source Link writes the file only for a known host, such as GitHub. CI clones from GitHub.

## Options considered

1. **Turn off Source Link** (`EnableSourceLink=false`). A debugger can no longer fetch the exact source of an assembly from the repository. These assemblies are built and tested in CI and never shipped, so nothing uses that.
2. **Keep Source Link and restore `sourcelink.json` from the cache.** The file names the commit that saved the entry, so a restored assembly would point at the wrong source. MSBuild would regenerate the file on the next build anyway.
3. **Leave it.** Every cache hit on a new commit recompiles, so the outputs cache saves nothing (D96).

## Decision

Option 1. `apps/backend/Directory.Build.props` sets `EnableSourceLink` to `false`, next to `IncludeSourceRevisionInInformationalVersion=false`.

The stale-binary test now gives its clone a GitHub-shaped origin, as CI has, so that Source Link would run if it were on. With Source Link on, the test failed three cases: a new commit with the same tree recompiled 7 of 7; a `Billing.Api` change compiled 7 and skipped 0 (expected 3 and 4); and the old design no longer shipped a stale binary, so the detector itself could not fail. With the flag, all three pass.

## Consequences

- A cache hit on a new commit skips CoreCompile for every project whose inputs are unchanged, on the runner as in the test.
- The PDBs of these assemblies no longer carry a Source Link map.
- The flag changes `Directory.Build.props`, which every project's output key reads, so the first build of each project after the merge misses and the next `master` push saves new entries.
- Any other build-time file that carries the commit id would break reuse the same way. The stale-binary test now runs with a GitHub-shaped origin, so it would catch such a file.
