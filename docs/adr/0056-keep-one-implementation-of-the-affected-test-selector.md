# 0056. Keep one implementation of the affected-test selector

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D87 in docs/platform/requirements.md

## Context

Line numbers below are those of the base commit of this change.

The .NET affected-test selector existed twice: `scripts/apps/dotnet-affected-test.sh` (149 lines) and a PowerShell port `scripts/apps/dotnet-affected-test.ps1` (250 lines), each with its own harness (`tests/verify-affected-graph.sh`, `tests/verify-affected-graph.ps1`).

- Only the shell script is on a product path. The pipeline action calls it at `.github/actions/run-affected-tests/action.yml:27`; nothing calls the PowerShell script.
- Only the shell script is mutation-tested. The mutation step of `.github/workflows/affected-selector-ci.yml` sets `src=scripts/apps/dotnet-affected-test.sh` (line 47); the PowerShell script has no mutant.
- The two have already drifted. The shell harness runs seven scenarios and the PowerShell harness six (`docs/handoff/testing.md:18`), and the PowerShell selector also reads untracked files (`dotnet-affected-test.ps1:64`), which the shell selector does not.
- They shared a defect. Both filtered test projects by matching "test" against the full path (`dotnet-affected-test.sh:59,67` and `dotnet-affected-test.ps1:112,120`), so a checkout path containing "test" selected every project. Fixing it meant changing and testing two programs.
- A Windows operator already has WSL (ADR 0010), where the shell script and harness run unchanged.

## Options considered

1. Keep both and add the missing scenarios and mutants to the PowerShell side — doubles the maintenance of a selector that CI never runs on Windows.
2. Keep the PowerShell port as a thin wrapper that calls the shell script through WSL — a third moving part for no new coverage.
3. Delete the PowerShell selector and its harness; the shell script is the only implementation.

## Decision

Option 3. `scripts/apps/dotnet-affected-test.ps1` and `tests/verify-affected-graph.ps1` are removed, together with the PowerShell harness step of `affected-selector-ci.yml`. `apps/README.md` points Windows operators to WSL.

## Consequences

- One program to fix, test and mutation-test; the harness and the mutants cover everything the pipeline runs.
- Windows operators run the selector and its harness in WSL; there is no native Windows path.
- Other documents still name the removed files and need the same edit: `AGENTS.md:78`, `docs/handoff/testing.md:18`, `docs/knowledge/test-catalogue.md:18,68,69`, `wiki/04-SDET-Transitive-Affected-Testing.md:5,24`, `standard/README.md:336` and `standard/criteria.tsv:21` (a covered path of check 5.1).
- Reverting is `git revert` of this change; no data or state is involved.
