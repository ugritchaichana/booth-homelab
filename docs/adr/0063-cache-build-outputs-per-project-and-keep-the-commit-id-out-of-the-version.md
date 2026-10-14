# 0063. Cache build outputs per project and keep the commit id out of the version

- Status: Accepted; amends the output key of [0049](0049-key-caches-by-content-and-restore-outputs-only-on-an-exact-match.md)
- Date: 2026-10-14
- Deciders: operator, for the owner's Phase 5 definition (D96)
- Decision log: D97 in docs/platform/requirements.md

## Context

D96 asks the load test to show that the cache is really used, and that a build reuses earlier cached outputs to beat a full build. Two measurements showed that the build-outputs cache did neither.

- **Live CI.** A hit did not shorten the build. On the Proxmox runner, builds that restored `dotnet-outputs` took 6.3 to 9.0 s (runs 37883089844, 37883326157, 37885262544, 37888483536). Builds that missed took 6.6 to 10.5 s (runs 37884692419, 37886398244, 37886845220, 37887034978).
- **Same tree, new commit.** A hit on a later commit with an identical `apps/` tree recompiled every project: CoreCompile ran 7 of 7 times. The same hit on the commit that saved the entry skipped all 7. The SDK writes the commit id into the generated `AssemblyInfo.cs` (`SourceRevisionId` in `InformationalVersion`). A new commit rewrites that file, so it is newer than every restored assembly. In CI almost every hit lands on a commit other than the one that saved it. A docs-only merge is one example.
- **One key for the whole tree.** A change to one file of any project missed the whole entry, so a one-project change rebuilt all seven.

In the 7-project sample, compiling or skipping takes the same wall time (4.9 s). A generated 24-project solution of 36,000 lines was measured once in WSL. Its cold build took 56 to 70 s. A hit on a new commit with the current flags took 53.4 s and skipped 0 of 24 projects. With the commit id left out it took 13.7 s and skipped 24 of 24. Editing the last project on top of restored outputs took 16.1 s and skipped 23 of 24. The Phase 5 benchmark repeats this on the runner.

## Options considered

1. **Keep one key for the tree and add the commit to it.** Every commit misses, so the cache is never used.
2. **Restore the newest entry of the branch and let MSBuild sort out the timestamps.** This is the stale-binary design that ADR 0049 removed (row 18).
3. **Per-project entries, keyed by exactly what the project's build reads.** Leave the commit id out of the version.

## Decision

Option 3.

- **The version.** `apps/backend/Directory.Build.props` sets `IncludeSourceRevisionInInformationalVersion` to `false`. The assembly's informational version no longer names the commit. Traceability comes from the run that built the assembly, not from the binary.
- **One entry per project.** The output key (schema 3) adds the project path. It replaces the tree ids of `apps/backend` and `apps/fixtures` with the object ids of the project's inputs:
  - the directory of every project in its `ProjectReference` closure;
  - every path a project file names outside its own directory (a `None`, `Compile` or other item, an `Import`, a `HintPath`; for a wildcard, its fixed leading directory);
  - every `Directory.Build.props`, `Directory.Build.targets`, `Directory.Build.rsp`, `Directory.Packages.props`, `global.json`, `nuget.config`, `.editorconfig` and `.globalconfig` in each of those directories or above.

  Platform, SDK version, configuration and workspace root stay in the key as before.
- **What cannot be keyed misses.** A project file that cannot be parsed, an include with an MSBuild expansion (`$(`, `@(`, `%(`), a path outside the repository, or a dirty input makes that project and every project that depends on it a miss. The other projects are unaffected.
- **Restore and save.** Restore looks up each project and extracts only under that project's directory, into `bin` and `obj`. It gives every restored file one timestamp, so restored projects never look newer than one another. The action reports `hit` (every project) and `restored` (for example `4/7`). Save writes each project's `bin` and `obj` as its own entry, and skips projects this job restored.
- **The test.** `tests/cache/test_stale_binaries.sh` builds, saves and restores the real solution. It now also requires:
  - a new commit with the same tree to skip CoreCompile in every project;
  - a change to `Billing.Api` alone to compile exactly the projects the affected-test selector lists (3) and skip the other 4, with the new code in the binary.

  Both cases failed before the change (7 of 7 recompiled each time) and pass after it.

## Consequences

- A one-project change reuses the cached outputs of every project that does not depend on it. A docs-only commit reuses all of them.
- The informational version of a built assembly no longer carries the commit id.
- One push writes up to one entry per project (7 here) instead of one. The bytes stored are about the same, because the old entry held the same `bin` and `obj` trees. Schema 2 entries become unreachable and age out under the LRU limit.
- A project's archive can write only under its own directory, which is narrower than the earlier `apps/backend` or `apps/fixtures` prefixes.
- Outputs stay keyed by the workspace root. On the three-instance runner an entry serves only the instance whose workspace built it, until every instance sees the same path (the Phase 5 runner change).
- Project-file parsing is a reading of MSBuild, not MSBuild itself. An input reached only through a property (`$(…)`) misses rather than risking a stale binary. An input the reader does not know about, for example a custom target that reads a file outside the project with no item for it, would not be in the key. The stale-binary test covers the inputs this repository uses.
