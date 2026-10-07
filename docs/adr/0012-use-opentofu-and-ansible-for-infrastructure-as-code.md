# 0012. Use OpenTofu and Ansible for infrastructure as code

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: D2 in docs/platform/requirements.md (requirement R4)

## Context

The platform must be reproducible from code (R2): VMs, containers, templates, networks, storage, users, API tokens and ACLs on Proxmox, plus the operating-system and service configuration inside each machine. The tree at this commit mixes both concerns: declarative stacks under `iac/tofu/` and `iac/ansible/`, and imperative provisioning scripts under `scripts/proxmox/` (`provision-runner.py`, `provision-minio.py`, and others).

Requirements from R4: idempotent runs, pinned tool versions, state with locking, and CI that runs format, validate, lint and plan. Extra tools are allowed only with a reason recorded in the decision log.

## Options considered

1. OpenTofu for Proxmox API objects plus Ansible for OS and service configuration — two well-known tools with a clear seam; no wrapper layer.
2. Terragrunt and mise on top — Terragrunt generates backend and variable boilerplate across many stacks or environments; mise pins tool versions. This lab has one stack type instantiated per host and a pinned bootstrap script, so both would be an extra layer with nothing to reduce yet.
3. Ansible alone, or the existing imperative scripts — fast to write, but Proxmox objects would have no plan step, no drift detection and no state, which R4 requires.

## Decision

Option 1, with one rule for who owns what:

| Concern | Tool |
|---|---|
| Objects reachable through the Proxmox API (VMs, CTs, templates, storage, networks, users, tokens, ACLs) | OpenTofu |
| Anything inside a machine's operating system (repositories, packages, hardening, firewall, services, runner and cache software) | Ansible |

- An imperative script is allowed only as a thin wrapper over one of the two.
- The exit gates are `tofu plan -detailed-exitcode` returning 0 after apply, and a second `ansible-playbook` run reporting `changed=0` on every host (R4).
- Tool versions are pinned in CI (`.github/workflows/iac-ci.yml`, `tofu_version`, for OpenTofu) and in the operator bootstrap (ADR 0010).
- Further tools (SOPS for secrets, tflint, ansible-lint) are added each with a recorded reason, not by default.

## Rationale and trade-offs

- The seam follows the API boundary: if a Proxmox call creates it, OpenTofu plans it; if the work happens after SSH login, Ansible converges it. Neither tool is asked to do the other's job.
- Accepted cost: two languages and two state models. Values that both need (addresses, sizes) must live in one place, handled through inventory data and flavor catalog (ADR 0017).
- The decision log records the owner's rule "best practice first" and does not give a further reason for choosing OpenTofu over its upstream; none is invented here.
- Revisit Terragrunt when more than one environment shares backend and variable boilerplate. Revisit the scripts under `scripts/proxmox/` as each is replaced by a stack or role.
