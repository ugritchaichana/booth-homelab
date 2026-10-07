## Description
<!-- What changes and why. Link the requirement row or decision (D<n>) and the ADR. -->

## Blast radius
<!-- What breaks and how many; furthest environment reached; time to detect; time to roll back. N/A is an answer. -->

## Evidence
<!-- Paste real output: CI run URL, converge/plan result, R15 summary. Host changes cannot run in hosted CI. Never paste a secret or a non-lab address. -->

## Checklist
- [ ] Title matches `^(feat|maintenance|refactor|fix|config|infra|chore|e2e|test): <subject>` (no scope in parentheses)
- [ ] At most 30 changed files
- [ ] Each new decision has an ADR and an index line; the decision log is updated
- [ ] A new check was shown red before green
- [ ] Tests for the area pass (`AGENTS.md`, section "Running the tests")
- [ ] No secret in the diff or on a command line; published evidence went through `scripts/evidence/publish.py`
- [ ] English only, no employer, organization or person names, lab addresses only
- [ ] Documentation updated where behavior changed
