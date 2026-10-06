# Infrastructure as Code

This directory holds the declarative provisioning and configuration code for the lab.

| Path | Purpose |
| :--- | :--- |
| [`inventory/`](./inventory/) | The single host data file read by Ansible and, later, OpenTofu (ADR 0021). |
| [`tofu/`](./tofu/) | OpenTofu configuration for Proxmox objects, plus the instance flavor catalog (`tofu/flavors.json`). |
| [`proxmox/`](./proxmox/) | Answer-file template for the unattended Proxmox VE install. |
| [`secrets/`](./secrets/) | SOPS-encrypted host secrets. |

The bootstrap scripts, cache policies and Ansible content of the previous host were retired (ADR 0020). Ansible content returns with the baseline role.

`scripts/iac/render-ssh-config.sh` renders the SSH config and pinned host keys from the inventory, and `scripts/iac/ansible.sh` runs Ansible with it (ADR 0022).

See [`tofu/README.md`](./tofu/README.md) for the execution guide.
