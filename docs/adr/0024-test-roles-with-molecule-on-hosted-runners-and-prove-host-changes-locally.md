# 0024. Test roles with Molecule on hosted runners and prove host changes locally

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D57 in docs/platform/requirements.md

## Context

The repository has no runner of its own in this phase, and the PVE VM is reachable only from the workstation. A role needs a test that runs on every pull request, and some behaviour (a second SSH login, a timed restore, a pending reboot) cannot run in a container.

## Options considered

1. Lint and syntax checks only — cheap, but nothing proves a role converges, is idempotent or leaves the intended state.
2. Molecule with the Docker driver on a GitHub-hosted runner, using a Debian 13 container that runs systemd — converge, idempotence and verify on every pull request.
3. A nested VM in CI or the PVE VM as the test target — closest to the host, but needs hardware or access that hosted runners do not give.

## Decision

Option 2 for roles that are provider-neutral, with the host-specific proof done locally and pasted into the pull request.

- `.github/workflows/iac-ci.yml` job `ansible-quality-gate`: `ansible-lint --profile production`, `--syntax-check` on every playbook, then `molecule test` in `iac/ansible/roles/base`. Its default sequence prints `Idempotence completed successfully` when a second converge changes nothing.
- The scenario's `verify.yml` asserts the effective state: `sshd -T` values, sudoers validity and mode, the automation account, root key restriction and revocation, chrony package, unit and sources, and the journal cap.
- The toolchain is a hash-locked `requirements-ci.txt` installed with `--require-hashes` on Python 3.13, the interpreter the lock was resolved under. The Molecule Docker driver needs `community.docker`, so it is pinned in `requirements.yml` beside the three collections the roles use.
- `base_container_test_mode` is the only switch that skips behaviour a container cannot run: the fresh-session checks, the dead-man and the chrony start. Its effect is documented in `iac/ansible/README.md`, and a real host never sets it.
- What stays proven locally: the guard in ADR 0023, `pve_*` roles, plan and apply, and the isolation proof. The output is recorded in the pull request.

## Rationale and trade-offs

- Measured 2026-10-07 in a disposable Debian 13 instance with systemd, using the scenario's own `prepare.yml`, `converge.yml`, `verify.yml` and variables: first converge applied, second converge `changed=0`, `verify` passed 17 tasks. Removing `PasswordAuthentication no` from the drop-in template made `verify` fail at the `sshd -T` assertion.
- Not measured: the Molecule run itself on a hosted runner, because no Docker daemon exists on the workstation. Treat the container build, privileged systemd start and cgroup mount as HYPOTHESIS until the first CI run.
- Accepted loss: test mode leaves the guard and the chrony start untested in CI, so a regression there shows only in the local proof.
- A change to `.ansible-lint` alone does not start the workflow, because the trigger paths stay `iac/**` and the workflow file.
