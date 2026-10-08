# Debt left by the previous agent

The inventory taken on 2026-10-07 is closed except for the items below, which now live in [limits-and-gaps.md](../handoff/limits-and-gaps.md) and [next-phases.md](../handoff/next-phases.md):

- the janitor for runs stuck on offline self-hosted runners (Phase 6 backlog, closed pull request #49);
- `global.json`, only if a template build ever picks the wrong SDK;
- the old copies of three renamed wiki pages, which stay on the GitHub wiki until the owner deletes them there.

Closed, merged or deleted items, and why, are in git history and [ADR 0020](../adr/0020-retire-the-bootstrap-cache-and-ansible-assets-of-the-previous-host-instead-of-porting-them.md). The red build on the retired host was a full runner disk, not the .NET code; CI runs on hosted runners until the pool exists ([ADR 0054](../adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md)).
