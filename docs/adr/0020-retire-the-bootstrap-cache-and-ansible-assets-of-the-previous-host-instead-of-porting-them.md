# 0020. Retire the bootstrap, cache and Ansible assets of the previous host instead of porting them

- Status: Accepted
- Date: 2026-10-06
- Deciders: operator
- Decision log: recorded as the retirement row of the Phase 2 plan, not as a numbered entry in docs/platform/requirements.md

## Context

The repository still carries assets written for a bare-metal Proxmox VE 8.x host (`iac/bootstrap/bootstrap.sh:3`). The current platform installs PVE 9 unattended into a VM (ADR 0004), keeps it off the tailnet (ADR 0008), runs Docker workloads in VMs (ADR 0015) and scales CI with ephemeral runners (ADR 0016). Read at commit `179f82606f06823ebb04773777d3d1fd8c2728ae`:

- `iac/bootstrap/bootstrap.sh:3` converts Debian to "Proxmox VE 8.x" and joins the tailnet (`06-install-tailscale.sh`). The unattended install (`iac/proxmox/answer.pve01.toml.tmpl`, `scripts/hyperv/`) replaces it.
- `iac/ansible/ansible.cfg:5,19` set `host_key_checking = False` and `StrictHostKeyChecking=no`.
- `iac/ansible/roles/enterprise_firewall/templates/homelab-firewall.j2:9-11,29-31` insert chains into `INPUT` and `FORWARD`, the chains pve-firewall manages. The role and its inventory use the retired subnet and old container names.
- `iac/ansible/roles/proxmox_host/tasks/main.yml:13,19` use `failed_when: false` on template downloads, which swallows failures.
- `iac/tofu/import-existing.sh:5` imports the retired containers into state.
- `.github/workflows/iac-ci.yml:48-78` installs ansible-core and syntax-checks the old playbooks; `scripts/proxmox/apply-enterprise-firewall.py:28` and `verify-enterprise-firewall.py:22` read the role's defaults file; `.github/pull_request_template.md:17` asks for that script's result.

## Options considered

1. Port the assets to PVE 9 — keeps working code, but the bootstrap is superseded by the unattended install, the firewall role competes with pve-firewall, and the runner and cache roles encode persistent runners and a cache store chosen before the current design.
2. Keep the assets dormant in the tree — no work now, but CI still runs against them, two scripts depend on the role, and a file that no longer matches the host misleads whoever reads it.
3. Retire them and keep the two useful references in history — the tree describes only the current host; the references stay readable at a fixed commit.

## Decision

Option 3, in two changes: the first removes the bootstrap scripts, the cache policies and the import scripts; the second removes the old Ansible tree, the two firewall scripts and the CI job that checked them, and makes the OpenTofu job find root modules by layout. The OpenTofu root module of the previous host is retired in a separate change once the new stack exists. Later phases rebuild what they need under the new layout.

Kept by commit `179f82606f06823ebb04773777d3d1fd8c2728ae`:
- the egress domain list, `iac/ansible/roles/enterprise_firewall/defaults/main.yml:9-36`;
- the bucket-scoped cache policies, `iac/minio/policies/build-cache-reader.json` and `build-cache-writer.json`.

## Rationale and trade-offs

- Each retired file has a stated reason above; none was retired for age alone.
- Accepted cost: working code is discarded and a later phase must rewrite it. The two references that carry design value stay one `git show` away.
- Until the rebuilt roles land, no Ansible content is checked in CI; the Ansible job is removed rather than stubbed so a green check cannot mean nothing ran.
- Revisit when a later phase needs the bucket-scoped policy pattern or the egress list; read them from the commit above rather than restoring the files.
