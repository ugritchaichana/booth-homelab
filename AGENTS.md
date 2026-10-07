# AGENTS.md

Guidance for any AI coding agent or human contributor working in this repository. It is vendor-neutral; `CLAUDE.md` only imports this file.

## What this repository is

A neutral homelab CI platform built for learning: Proxmox VE 9 as a Hyper-V VM on a Windows workstation, built from code (OpenTofu + Ansible, SOPS + age), with two-layer guest isolation, golden templates, a build cache and flavor-sized guests. What is built and what is handed off: the phase table in `docs/handoff/README.md`. Overview: `README.md`. Operations: `RUNBOOK.md`.

## Sources of truth

| Question | Read |
|---|---|
| What is required, what was measured, which decision was taken | `docs/platform/requirements.md` (requirements `R1`..., measured rows, decisions `D1`... each with its topic) |
| Why a choice was made | `docs/adr/` (index in `docs/adr/README.md`) |
| What a run proved | `docs/evidence/<phase>/INDEX.md` |
| Defects the real host exposed, what each test proves | `docs/knowledge/` |
| What is not built | `docs/handoff/README.md` |

Never delete earlier content of the requirements document: mark a changed decision `SUPERSEDED` and append the new one. The same goes for ADRs: write a new one and add "Superseded by NNNN" to the old.

## Identity and process

- Commit only with the identity configured for this repository. Never commit with a work or employer identity; check `git config user.email` first.
- Every change goes through a pull request. The agent opens it and never merges; the owner merges.
- PR title: `^(feat|maintenance|refactor|fix|config|infra|chore|e2e|test): <subject>`. A bare type and a colon, no scope in parentheses.
- At most 30 changed files per pull request. Split a larger change, even a mechanical one.
- Document first: scope, open questions and a blast-radius estimate (what breaks and how many, furthest environment reached, time to detect, time to roll back) are written before work starts.
- One ADR per finalized decision, in the pull request that finalizes it (`docs/adr/README.md` has the template and the file-name rule). Add the index line and the decision-log row.
- Host changes (converge, `tofu apply`, R15 runs) cannot run in hosted CI. Run them locally and paste the real output into the pull request body.

## Neutrality and language

- English only, in code, comments, commits, pull requests and docs (ADR 0002).
- Name no employer, organization, team or person. Say "owner", "maintainers" or "the previous agent".
- Use only lab addresses (`10.99.0.0/16`) and documentation ranges. Real hostnames, user names and non-lab addresses stay out of the repository and out of published evidence.
- Check for Thai text before pushing:

```sh
python3 -c "import subprocess,re,sys;p=re.compile('['+chr(3584)+'-'+chr(3711)+']');bad=[f for f in subprocess.check_output(['git','ls-files'],text=True).splitlines() if p.search(open(f,encoding='utf-8',errors='ignore').read())];print(bad or 'ok');sys.exit(bool(bad))"
```

## Secrets

- Secrets live in SOPS files under `iac/secrets/` (one file per consumer and host, one writer each) and in GitHub environment secrets. Never commit decrypted output or an age identity.
- Never put a secret on a command line (`argv`): pass it on stdin (`sops set --value-stdin`) or through the environment of one process. Never print one; print names only.
- Rotate by changing the value, not by re-encrypting it: old commits stay decryptable.
- `gitleaks` runs in CI and as a pre-commit hook.

## Evidence

- Publish run output with `scripts/evidence/publish.py`; read `docs/knowledge/README.md` first. Raw files, the value map and the deny list stay on the operator's machine.
- A published file is never hand-edited. When the checker flags a value, extend the map and run the publisher again.
- Check what is committed: `python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac`.
- Every number in a document cites a requirements row, an evidence file or a run id. If you cannot back a number, remove it.

## Engineering rules

- Test first: a new check must be shown red before it is green. A test that never failed proves nothing.
- Never buy speed with a false green: do not narrow a check, unskip to pad a denominator or soft-fail a step.
- One owner per object: Ansible owns OS configuration, the API identity and the firewall files; OpenTofu owns SDN, guests and guest firewall options (ADR 0025).
- Keep host-specific code (Hyper-V, Windows firewall) apart from the portable core (Proxmox roles, stacks, templates, workflows).
- Pin tools by version and hash. Pin third-party actions by commit SHA.
- Shell scripts use LF line endings (`.gitattributes`). Windows scripts stay compatible with PowerShell 5.1. Commands written for users on Windows use `cmd` syntax.
- Comments are rare: say why, never what. No changelog in comments.

## Running the tests

The command list is `RUNBOOK.md` 4.1, "Offline suites (no host)", run from the repository root in WSL Debian after `scripts/bootstrap/operator-toolchain.sh`. What each test proves, its command and its CI job: `docs/knowledge/test-catalogue.md`. The sample solution runs with `dotnet test apps/backend/SdetTestingRig.sln` and `npm ci && npm test --prefix apps/frontend`.

During an iteration run only the test of the file you changed; run the whole set once at the end. Every new test gets a catalogue row.

## Working on the host

Operator commands run from WSL through the wrappers in `scripts/iac/`, which render the pinned SSH config, open the API forward and keep state encrypted. Do not call `tofu` or `ansible-playbook` directly against the host. Before a change that could lock you out of SSH or the firewall, read the dead-man description in `iac/ansible/README.md`. A converge can apply pending package updates and reboot the host. Procedures: `RUNBOOK.md`.
