# 0057. Measure coverage with coverage.py and Pester

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D88 in docs/platform/requirements.md

## Context

The owner asked for the coverage numbers. Pester already prints command coverage for the Hyper-V module. The three Python suites (`tests/cache`, `tests/evidence`, `standard/tests`) printed none. The shell tests, the Ansible roles and the OpenTofu stacks have no line-coverage tool wired into CI. Python CI installs only hash-pinned requirements, so a new tool must be pinned the same way.

## Options considered

1. Pester for PowerShell and coverage.py with branch measurement for Python, a floor per suite, and an inventory for roles and stacks.
2. Add kcov to the shell-test jobs. `ubuntu-latest` is Ubuntu 24.04, whose archive has no `kcov` source package (22.04 has 38, 25.04 has 43), so the apt install fails there; building it from source or fetching a binary adds a pinned artifact for a number nobody gates on.
3. Gate on a fixed target such as 95%. The suites measure 86%, 94% and 89%; a target above the measurement fails the first run and invites tests written for the number.

## Decision

Option 1.

- coverage.py 7.16.2, pinned with every distribution hash in `tests/requirements-coverage-ci.txt`, one file shared by `cache-ci.yml`, `evidence-ci.yml` and `standard-scorecard.yml` (the cache job installs it next to its PyYAML file). The two path-filtered workflows list the file as a trigger.
- Each job runs the existing unittest command under `coverage run --branch --source=<package>`, prints `coverage report -m --precision=2` and the line and branch split.
- The scorecard tests run the scorer as a child process, which direct measurement misses entirely. That job writes a two-line configuration to the runner temp directory and sets `patch = subprocess`, then runs `coverage combine` before the report.
- The floor is the lowest recorded total, across the hosted CI run and the local runs, rounded down to the whole percent: 86 for the cache client (CI 89.38%, WSL 86.05%), 94 for the evidence publisher, 89 for the scorecard. It is a regression guard and is raised only after a measured gain; it changes no assertion. `--precision=2` is part of the command: at the default precision of zero a total of 94.99% rounds to 95 and passes `--fail-under=95`.
- Pester coverage for the Hyper-V module stays as it is in `hyperv-ci.yml`.
- kcov results are reported from a local run only, on the two scripts named in `docs/knowledge/coverage.md`, with no CI job and no gate.
- Ansible roles and OpenTofu stacks are reported as an inventory (which test exercises which role and how; `run` blocks per stack), never as a percentage.

## Consequences

- A change that removes tests or adds untested code in one of the three Python packages fails CI once the total drops below the floor.
- The cache floor follows the WSL figure (86.05%), so the hosted run keeps a margin of about 3 points; the cause of the gap between the two environments is not established. The step output shows the number to decide between restoring a test and moving the floor.
- The evidence and cache numbers differ by platform for a few lines; the Linux figure is binding because CI runs on Linux.
- Shell, role and stack coverage remain unmeasured by tool. Revisit kcov when the hosted image has a package or the runner pool image carries it.
