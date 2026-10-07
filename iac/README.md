# Infrastructure as Code

This directory holds the declarative provisioning and configuration code for the lab.

| Path | Purpose |
| :--- | :--- |
| [`inventory/`](./inventory/) | The single host data file read by Ansible and, later, OpenTofu (ADR 0021). |
| [`ansible/`](./ansible/) | Playbooks, the `base` role and its Molecule scenario (ADR 0023, ADR 0024). |
| [`tofu/`](./tofu/) | OpenTofu configuration for Proxmox objects, plus the instance flavor catalog (`tofu/flavors.json`). |
| [`proxmox/`](./proxmox/) | Answer-file template for the unattended Proxmox VE install. |
| [`secrets/`](./secrets/) | SOPS-encrypted host secrets. |

The bootstrap scripts, cache policies and Ansible content of the previous host were retired (ADR 0020). The baseline role replaces them (ADR 0023).

`scripts/iac/render-ssh-config.sh` renders the SSH config and pinned host keys from the inventory, and `scripts/iac/ansible.sh` runs Ansible with it (ADR 0022).

See [`tofu/README.md`](./tofu/README.md) for the execution guide.
