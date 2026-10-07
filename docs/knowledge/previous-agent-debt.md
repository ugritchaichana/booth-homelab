# Debt left by the previous agent

Inventory taken on 2026-10-07 against the repository as it stands after the 40-pull-request chain, plus the nine open pull requests the previous agent left. Each item has a verdict: closed, deleted, kept, or fixed. Neutral record; the reasons are the point, so nothing is listed without one.

## Open pull requests

The checks on all nine were red for one reason that is not their diffs: their jobs ran on the retired host's runners and failed at checkout with `No space left on device`, or waited 24 hours in the queue (runs 37353566718, 37354255423, 37354886298, 37355482793, 37409977494, 37409978132, 37409989062).

| Pull request | Verdict | Reason |
|---|---|---|
| #48 self-healing runner containers | Closed | Targets the retired host's persistent runners; ephemeral runners that are destroyed after one job replace the idea (ADR 0016), and the modules and roles it touches no longer exist |
| #49 janitor for runs stuck on offline self-hosted runners | Closed, kept as backlog | Not needed until the Phase 5 pool exists; the script is portable and is listed in `docs/handoff/` to be re-introduced with the pool's labels |
| #50 private temp paths for a runner token | Closed | Touches only retired provisioning files; the new runner path already uses a private temporary file |
| #51 cache upload gated to a writer job | Closed | The object-store writer path is replaced by `bazel-remote` with one writer credential (ADR 0048, 0049, 0050); the writer-gated jobs already exist in the reusable pipeline |
| #52 SDK 10 next to SDK 8 and a pinned `global.json` | Closed | Both SDKs are baked into the golden template (ADR 0042); ADR 0049 records that locked restore passes on both SDKs, so no `global.json` was added |
| #53 monthly hosted-runner fallback drill | Kept open | Contains nothing from the retired host and proves CI survives losing the host; merge after the chain |
| #54 back every numeric claim in docs with a run or remove it | Closed | The pages it edits are rewritten in this release; its rule is applied there and lives on in the scorecard check |
| #55 scorecard and evidence ledger | Kept open, rework | Requirements cite it; it still names a team in its README and four records and points at retired paths, so it needs those fixed and a rebase before merge |
| #56 vendor-neutral agent guide | Closed | Superseded by the rewritten `AGENTS.md`, the one-line `CLAUDE.md` import and `docs/handoff/`; the vendor-specific guide and the work-identity text are removed with it |

## Files of the retired host

The scripts, the sandbox and the docs below referred to the retired host (its addresses, its runner containers, its object-store cache). No workflow, test or script used them; only docs referred to them. The history is kept in git; ADR 0020 records the decision.

| Item | Verdict | Reason |
|---|---|---|
| Nine PVE 8 and container provisioning scripts under `scripts/proxmox/` | Deleted | Hard-code the retired host and its cache; no referrer outside docs |
| Four one-shot scripts under `scripts/ci/` (project-board population, PR linking, labels, the container-103 test runner) | Deleted | One-off, with hard-coded IDs and retired-host addresses, or an SSH path to a container that no longer exists. The current Angular tests run through `scripts/apps/run-angular-jest.sh` |
| `sandbox/` (object-store compose setup and its policies) | Deleted | The cache it imitated is replaced by `bazel-remote` |
| `scripts/proxmox/build-auto-install-iso.sh`, `scripts/proxmox/ephemeral/` | Kept | Part of the current install and runner design |
| Old root docs (`AI_CONTEXT.md`, `HANDOFF.md`, the vendor-specific guide) and the old wiki pages | Replaced | Rewritten as `AGENTS.md`, `docs/handoff/` and the current wiki; three renamed wiki pages need an owner step, see `docs/knowledge/README.md` |
| Runner descriptions in `.github/actions/run-angular-jest/action.yml` and a flavor description in `iac/tofu/flavors.json` | Fixed | One-line wording changes |
| `.github/workflows/wiki-sync.yml` ran on labels no runner has | Fixed | Runs on a hosted runner; the script needs only Python and the repository token. The `|| true` on its sync step still masks failures and is recorded as a follow-up |
| The two registered but offline runners of the retired host | Open, owner step | Deregistering needs an administration token and is the Phase 6 cutover step |

## The red build on the old master

The last master run on the retired host (run 37341728563, attempt 2) failed in `Test (Angular)` at checkout with `No space left on device`; `Report` failed only because it counts that failure. `Build (.NET)`, `Test (.NET)` and `Cache (.NET)` in that run were green, so the .NET code was not broken: the cause was the full disk of a retired runner. The merged tree builds and passes on hosted runners (run 37602620111: `Build succeeded`, tests and Angular green). Own-repository jobs stay red or queued unless they run hosted, which is why CI runs on hosted runners until the pool exists (ADR 0054).

## Claims that were removed or are still open

- "Ephemeral mode (opt-in, unverified)" described scripts that are deleted; the measured runner path is a Phase 5 item.
- Throughput and timing figures in the old README and wiki that no cited run prints, and competitor comparisons, are removed. Every figure in the rewritten docs cites a requirements row or a run.
- Open in the backlog: the janitor (above), the scorecard rework, the `|| true` on the wiki sync, and a `global.json` only if a template build ever picks the wrong SDK.
