# Session Handover

**Operator:** An AI coding agent working through pull requests. The owner reviews and merges.
**State as of:** 2026-10-06

---

## Current State

- The previous Proxmox VE host is retired. Its self-hosted runners stay registered until a planned cutover, which needs the owner's go.
- Platform v2 is Proxmox VE 9 running under Hyper-V on a workstation.
- Platform v2 requirements are agreed and are being published in `docs/platform/requirements.md` (pending pull request).
- Implementation waits for the owner's go.

---

## Read Order

1. `AGENTS.md`
2. `docs/platform/requirements.md` (once its pull request is merged)
3. `RUNBOOK.md`
4. `wiki/`

---

## Rules

- Sections 8 to 10 of `AGENTS.md` apply: pull requests only, personal identity only, English only, circuit breaker.
- Never use or print a credential found in history.
- Do not connect to the retired host.
- No cutover, deletion or account-level action without the owner's go.

---

## How to Resume

1. Sync `master`: `git switch master`, then `git pull --ff-only`.
2. List open pull requests: `gh pr list`.
3. Read the requirements, then ask the owner which item to start.
