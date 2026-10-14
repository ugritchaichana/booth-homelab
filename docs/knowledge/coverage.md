# Test coverage

Line coverage where a tool exists, an inventory where it does not. "Line" is statements executed; "branch" is branch arcs taken (`coverage run --branch`); "condition" is every atomic condition seen both true and false (`tests/condition_coverage.py`). The gate is the combined figure that `coverage report` prints, which is what `--fail-under` compares. Floors are the lowest recorded total rounded down to the whole percent; they guard against regression and do not change what a test checks.

Measured on 2026-10-07 at commit 4447396 plus the workflow changes of this page. The Python figures are from Linux (Python 3.13, the hosted runner's version) and Windows (Python 3.12); CI on the hosted runner printed the gated totals: cache client 89.38% (cache-ci run 37630718473), evidence publisher 94.75% (evidence-ci run 37630718263), scorecard 89.52% (standard-scorecard run 37631138877). The floor is the lowest recorded total rounded down, so the same command passes locally and in CI.

## Coverage numbers

| Component | Tool | Number | Reproduce | Source |
|---|---|---|---|---|
| `scripts/hyperv/HomelabHyperV.psm1` | Pester 5.7.1 code coverage, pwsh 7 | 99.26% commands (803 of 809) | `pwsh tests/hyperv/Invoke-HyperVTests.ps1 -PesterVersion 5.7.1` | [hyperv-ci run, job "Pester tests and coverage (pwsh)"](https://github.com/ugritchaichana/booth-homelab/actions/runs/37628499263) |
| same module, Windows PowerShell 5.1 | Pester 5.7.1 code coverage | 99.01% commands (801 of 809) | `powershell -File tests/hyperv/Invoke-HyperVTests.ps1 -PesterVersion 5.7.1` | [hyperv-ci run, job "Pester tests and coverage (powershell)"](https://github.com/ugritchaichana/booth-homelab/actions/runs/37628499263) |
| `scripts/ci/build_cache` | coverage.py 7.16.2 and `tests/condition_coverage.py --package-root scripts/ci` | lines 889 of 889, branches 230 of 230, conditions 167 of 167 over the 12 modules with code (100%); floor 100 for all three (2026-10-14, WSL with `zstd`, 244 tests) | `coverage run --branch --source=scripts/ci/build_cache -m unittest discover -s tests/cache -p 'test_*.py'`, `coverage report -m --fail-under=100`, then per module `python3 tests/condition_coverage.py <module> tests/cache --package-root scripts/ci --fail-under 100` | `cache-ci.yml`, steps "Unit tests and dependency rule, measured" and "Condition coverage, every module" |
| `scripts/evidence` | coverage.py 7.16.2 | Linux combined 94.75% (lines 96.17%, branches 90.57%); Windows combined 94.99% (lines 96.49%, branches 90.57%); floor 94 | `coverage run --branch --source=scripts/evidence -m unittest discover -s tests/evidence` then `coverage report -m --precision=2 --fail-under=94` | `evidence-ci.yml`, step "Run the Publisher and Checker Unit Tests, Measured"; [Linux log](../evidence/closeout/coverage/python-evidence-linux.txt), [Windows log](../evidence/closeout/coverage/python-windows.txt) |
| `standard/scorecard.py` | coverage.py 7.16.2 with `patch = subprocess` | Linux and Windows combined 89.52% (lines 92.13%, branches 82.86%); floor 89 | `printf '[run]\nbranch = True\npatch = subprocess\n' > rc`, `COVERAGE_RCFILE=rc coverage run --branch --source=standard --omit='standard/tests/*' standard/tests/test_scorecard.py`, `coverage combine`, `coverage report -m --precision=2 --fail-under=89` | `standard-scorecard.yml`, job "Scorecard", step "Scorecard unit tests, measured through the scorer subprocess"; [Linux log](../evidence/closeout/coverage/python-standard-linux.txt), [Windows log](../evidence/closeout/coverage/python-windows.txt) |
| `scripts/ci/runner_route.py` | coverage.py 7.16.2 and `tests/condition_coverage.py` | lines 168 of 168, branches 66 of 66, conditions 64 of 64 (100%); floor 100 for all three (2026-10-09, WSL and CI) | `coverage run --branch --include='scripts/ci/runner_route.py' -m unittest discover -s tests/router`, `coverage report -m --fail-under=100`, then `python3 tests/condition_coverage.py scripts/ci/runner_route.py tests/router` | `report-ci.yml`, job "Runner Router Tests" |
| `scripts/ci/run_report.py` | coverage.py 7.16.2 and `tests/condition_coverage.py` | lines 241 of 241, branches 82 of 82, conditions 72 of 72 (100%); floor 100 for all three (2026-10-09, WSL and CI) | the same three commands with `run_report.py` and `tests/report` | `report-ci.yml`, job "Run Report Parser Tests" |
| `scripts/ci/load_test.py` | coverage.py 7.16.2 and `tests/condition_coverage.py` | lines 218 of 218, branches 54 of 54, conditions 64 of 64 (100%); floor 100 for all three (2026-10-14, WSL) | the same three commands with `load_test.py` and `tests/loadtest` | `report-ci.yml`, job "Load Test Driver Tests" |
| `scripts/ci/select-runner.sh`, `sdet-classify.sh`, `attempt-lib.sh` | kcov 43 (local only) | lines 28 of 28, 25 of 25, 25 of 25 (2026-10-09) | `SCRIPT_COVERAGE="kcov --include-path=<the three script paths> out" python3 -m unittest discover -s tests/router -p test_route_scripts.py`, then `out/kcov-merged/cobertura.xml` | local; no CI job (no kcov on `ubuntu-latest`, see below); 27 mutants of the three scripts are all caught by the same tests |
| `scripts/iac/new-guest.sh` | kcov 43 (local only) | lines 97.83% (45 of 46) | `kcov --include-path="$PWD/scripts/iac/new-guest.sh" out tests/isolation/test-new-guest.sh` | [local log](../evidence/closeout/coverage/kcov-new-guest.txt); no CI job |
| `scripts/apps/dotnet-affected-test.sh` | kcov 43 (local only) | lines 80.68% (71 of 88) | `kcov --include-path="$PWD/scripts/apps/dotnet-affected-test.sh" out tests/verify-affected-graph.sh` | [local log](../evidence/closeout/coverage/kcov-selector.txt); no CI job |

Notes on the numbers:

- `standard/tests/test_scorecard.py` runs the scorer as a child process, so without `patch = subprocess` the figure is 0.00% (0 of 178 statements). The same switch changes neither the cache nor the evidence figure, so those two run without a configuration file.
- `scripts/ci/build_cache/__main__.py` is covered by `tests/cache/test_entrypoint.py`, which starts the package with `-m`; the condition step skips it and the empty `__init__.py`, which have no decision; instrumenting either breaks the entry-point test.
- The cache figures need the `zstd` binary, which `ubuntu-latest` has: without it 4 tests skip and the real-binary path of `tar_archiver.py` (lines 121 and 125-146) is not run, so the gate is met on Linux with `zstd` only. Two operands that could never be true were removed rather than covered: `inflater.unconsumed_tail` after a decompress capped at `limit + 1` (output that stops at the cap is already over the limit) and the `"."` filter on `PurePosixPath(...).parts` (pathlib drops `.` parts).
- kcov is not measured in CI. Ubuntu 24.04, which `ubuntu-latest` is (the image field of [evidence-ci run 37621344079](https://github.com/ugritchaichana/booth-homelab/actions/runs/37621344079) reads `ubuntu-24.04`), has no `kcov` source package: the Launchpad archive lists 38 for 22.04 and 43 from 25.04, none for 24.04. The two shell figures are from Debian 13 with kcov 43 and bash 5.2.37.
- A branch figure is arcs between lines, so every operand of `a and b`, the test of `x if c else y` and a comprehension filter can stay untested at 100% branch. `tests/condition_coverage.py` instruments a module, runs its test directory, and requires each atomic condition of a decision to be seen true and false. Literals, the script's main guard and the last operand of an `and`/`or` used as a value (`value or default`, whose truthiness decides nothing) are not conditions; its own tests prove it reports a short-circuited operand and skips a value fallback. The first measurements were 40 of 45 conditions for the router and 36 of 73 for the report parser.
- kcov reported the closing line of a redirected brace group, a multi-line command substitution and `done < <(...)` as not executed although the tests assert their effects; the three router scripts write those constructs on one line, so their figures count every line. Shell has no branch or condition tool here: the mutants stand in for it.
- `scripts/ci/sdet-report.sh` has no unit test: it is verified by live callback runs only ([ADR 0061](../adr/0061-report-each-sdet-run-on-its-pull-request-from-a-workflow-run-callback.md)).
- Shell coverage is of the script under test only; the other 18 `tests/isolation/test-*.sh` files and their scripts are not measured.

## Inventory without a line-coverage tool

Counted on the merged close-out tree. [The raw output](../evidence/closeout/coverage/inventory-counts.txt) was taken at commit 4447396, before the guest-name tests added one `cache-service` and two `r15-probe` run blocks (10 and 22 there).

| Ansible role | Exercised by | How |
|---|---|---|
| `base` | `iac/ansible/roles/base/molecule/default` | Molecule converge, idempotence and verify in a Debian 13 container (`iac-ci.yml`, job "Ansible Lint, Syntax & Molecule") |
| `cache_service` | `test-cache-service-role.sh`, `test-cache-verify-cas.sh`, `test-cache-wait-for-address.sh` | template render and static checks with mutations; role helper scripts run directly |
| `hyperv_guest` | `test-role-hyperv-guest.sh` | role run with fake modules (`tests/isolation/lib/fake-role-module.py`) |
| `pve_api_identity` | `test-pve-api-identity-grants.sh` | real `ansible-playbook` run of the role's grant computation, asserting the result |
| `pve_firewall` | `test-cluster-fw-render.sh`, `test-guest-fw-guard.sh` | template render of `cluster.fw.j2`; the guard script run against a fake `pvesh` |
| `pve_host` | `test-role-pve-host.sh` | role run with fake modules |
| `pve_templates` | `test-template-build.sh`, `test-template-guest-step.sh`, `test-template-finalize.sh`, `test-template-units.sh`, `test-template-content.sh`, `test-template-content-vm.sh` | orchestrator against `fake-pve.py`, fake `ssh`, fake root, template render, and a bundle linter |

Roles: 7, all with at least one test. Only `base` runs against a real system.

| OpenTofu stack | Test files | `run` blocks |
|---|---|---|
| `cache-service` | 1 | 11 |
| `guest` | 1 | 25 |
| `proxmox-host` | 3 | 20 |
| `r15-probe` | 2 | 24 |
| Total | 7 | 80 |
