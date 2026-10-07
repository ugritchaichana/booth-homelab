# Infrastructure as Code

Declarative provisioning and configuration of the lab: OpenTofu for infrastructure objects, Ansible for everything inside the host, SOPS + age for secrets (ADR 0012). Each object has exactly one owner (ADR 0025).

| Path | Purpose |
|---|---|
| [`inventory/`](./inventory/) | The single host data file read by Ansible and OpenTofu: `hosts.yml` (Proxmox hosts, guest and cache networks, cache endpoint), `cache.yml` (the cache container), `group_vars/`, `host_vars/` (ADR 0021). |
| [`ansible/`](./ansible/README.md) | Playbooks and roles: baseline, Hyper-V guest hardening, Proxmox host, API identity, firewall, golden templates, cache service. |
| [`tofu/`](./tofu/README.md) | OpenTofu stacks `proxmox-host`, `cache-service`, `r15-probe`; modules for the SDN, flavors and template lookup; the flavor catalog `flavors.json`. |
| [`policy/runner-class.yml`](./policy/runner-class.yml) | Per-guest firewall policy of the runner class, read by the template build, the probe stack and the cache stack. |
| [`proxmox/`](./proxmox/) | Answer-file template for the unattended Proxmox VE install. |
| [`secrets/`](./secrets/README.md) | SOPS-encrypted host and OpenTofu secrets. |

## Who owns what

| Object | Owner |
|---|---|
| OS configuration, sshd, the host and cluster firewall files, the OpenTofu API identity, base images, snippets, the template build framework, the cache service inside its container | Ansible |
| SDN zone and vnets, guests (probe, cache container), guest firewall options, template lookup | OpenTofu |
| Storage definitions | As the installer made them (ADR 0035) |

## Entry points

Run both tools only through the wrappers in `scripts/iac/`. They render the SSH config with the host key pinned from SOPS, open the API forward and keep OpenTofu state encrypted on the WSL filesystem (ADR 0022, 0029).

```sh
bash scripts/iac/ansible.sh site.yml                      # steady state
bash scripts/iac/tofu.sh proxmox-host pve01 plan          # then apply
```

Start with [`tofu/README.md`](./tofu/README.md) and [`ansible/README.md`](./ansible/README.md); procedures are in `RUNBOOK.md`. The bootstrap scripts, cache policies and Ansible content of the previous host were retired instead of ported (ADR 0020).

## CI

`iac-ci.yml` runs on every change under `iac/` and `tests/isolation/`: `tofu fmt`, tflint, `init`, `validate` and `test` per root module; ansible-lint (production profile), syntax checks, every `tests/isolation/test-*.sh` and Molecule for the `base` role (ADR 0024). Host changes are proven locally and pasted into the pull request.
