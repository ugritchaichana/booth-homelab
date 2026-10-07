# Test coverage

Line coverage where a tool exists, an inventory where it does not. "Line" is statements executed; "branch" is branch arcs taken (`coverage run --branch`). The gate is the combined figure that `coverage report` prints, which is what `--fail-under` compares. Floors are the measured Linux total rounded down to the whole percent; they guard against regression and do not change what a test checks.

Measured on 2026-10-07 at commit 4447396 plus the workflow changes of this page. The Python figures are from Linux (Python 3.13, the hosted runner's version) and Windows (Python 3.12); the Linux figure is the one that sets the floor. The three Python workflow steps print their numbers on the first run after merge; until then the raw local logs are the source.

## Coverage numbers

| Component | Tool | Number | Reproduce | Source |
|---|---|---|---|---|
| `scripts/hyperv/HomelabHyperV.psm1` | Pester 5.7.1 code coverage, pwsh 7 | 99.26% commands (803 of 809) | `pwsh tests/hyperv/Invoke-HyperVTests.ps1 -PesterVersion 5.7.1` | [hyperv-ci run, job "Pester tests and coverage (pwsh)"](https://github.com/ugritchaichana/booth-homelab/actions/runs/37628499263) |
| same module, Windows PowerShell 5.1 | Pester 5.7.1 code coverage | 99.01% commands (801 of 809) | `powershell -File tests/hyperv/Invoke-HyperVTests.ps1 -PesterVersion 5.7.1` | [hyperv-ci run, job "Pester tests and coverage (powershell)"](https://github.com/ugritchaichana/booth-homelab/actions/runs/37628499263) |
| `scripts/ci/build_cache` | coverage.py 7.16.2 | Linux combined 86.05% (lines 88.20%, branches 77.42%); Windows combined 86.37% (lines 88.74%, branches 76.88%); floor 86 | `coverage run --branch --source=scripts/ci/build_cache -m unittest discover -s tests/cache -p 'test_*.py'` then `coverage report -m --precision=2 --fail-under=86` | `cache-ci.yml`, step "Unit tests and dependency rule, measured"; [Linux log](../evidence/closeout/coverage/python-cache-linux.txt), [Windows log](../evidence/closeout/coverage/python-windows.txt) |
| `scripts/evidence` | coverage.py 7.16.2 | Linux combined 94.75% (lines 96.17%, branches 90.57%); Windows combined 94.99% (lines 96.49%, branches 90.57%); floor 94 | `coverage run --branch --source=scripts/evidence -m unittest discover -s tests/evidence` then `coverage report -m --precision=2 --fail-under=94` | `evidence-ci.yml`, step "Run the Publisher and Checker Unit Tests, Measured"; [Linux log](../evidence/closeout/coverage/python-evidence-linux.txt), [Windows log](../evidence/closeout/coverage/python-windows.txt) |
| `standard/scorecard.py` | coverage.py 7.16.2 with `patch = subprocess` | Linux and Windows combined 89.52% (lines 92.13%, branches 82.86%); floor 89 | `printf '[run]\nbranch = True\npatch = subprocess\n' > rc`, `COVERAGE_RCFILE=rc coverage run --branch --source=standard --omit='standard/tests/*' standard/tests/test_scorecard.py`, `coverage combine`, `coverage report -m --precision=2 --fail-under=89` | `standard-scorecard.yml`, job "Scorecard", step "Scorecard unit tests, measured through the scorer subprocess"; [Linux log](../evidence/closeout/coverage/python-standard-linux.txt), [Windows log](../evidence/closeout/coverage/python-windows.txt) |
| `scripts/iac/new-guest.sh` | kcov 43 (local only) | lines 97.83% (45 of 46) | `kcov --include-path="$PWD/scripts/iac/new-guest.sh" out tests/isolation/test-new-guest.sh` | [local log](../evidence/closeout/coverage/kcov-new-guest.txt); no CI job |
| `scripts/apps/dotnet-affected-test.sh` | kcov 43 (local only) | lines 80.68% (71 of 88) | `kcov --include-path="$PWD/scripts/apps/dotnet-affected-test.sh" out tests/verify-affected-graph.sh` | [local log](../evidence/closeout/coverage/kcov-selector.txt); no CI job |

Notes on the numbers:

- `standard/tests/test_scorecard.py` runs the scorer as a child process, so without `patch = subprocess` the figure is 0.00% (0 of 178 statements). The same switch changes neither the cache nor the evidence figure, so those two run without a configuration file.
- `scripts/ci/build_cache/__main__.py` is 0.00% (3 statements): no test starts the package with `-m`.
- The Linux and Windows cache figures differ because `fs_store.py:61-65` and `tar_archiver.py:94` run on one platform only. The Linux figure is within 0.05 points of its floor, so one lost line fails the gate; lower the floor by one point if a runner proves it flaky, and raise it only after a measured gain.
- kcov is not measured in CI. Ubuntu 24.04, which `ubuntu-latest` is (the image field of [evidence-ci run 37621344079](https://github.com/ugritchaichana/booth-homelab/actions/runs/37621344079) reads `ubuntu-24.04`), has no `kcov` source package: the Launchpad archive lists 38 for 22.04 and 43 from 25.04, none for 24.04. The two shell figures are from Debian 13 with kcov 43 and bash 5.2.37.
- Shell coverage is of the script under test only; the other 18 `tests/isolation/test-*.sh` files and their scripts are not measured.

## Inventory without a line-coverage tool

Counted from the tree; the counts are in [the raw output](../evidence/closeout/coverage/inventory-counts.txt).

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
| `cache-service` | 1 | 10 |
| `guest` | 1 | 25 |
| `proxmox-host` | 3 | 20 |
| `r15-probe` | 2 | 22 |
| Total | 7 | 77 |
