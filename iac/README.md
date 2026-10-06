# Infrastructure as Code

This directory holds the declarative provisioning and configuration code for the lab.

| Path | Purpose |
| :--- | :--- |
| [`tofu/`](./tofu/) | OpenTofu configuration for Proxmox objects, plus the instance flavor catalog (`tofu/flavors.json`). |
| [`proxmox/`](./proxmox/) | Answer-file template for the unattended Proxmox VE install. |
| [`secrets/`](./secrets/) | SOPS-encrypted host secrets. |

The bootstrap scripts, cache policies and Ansible content of the previous host were retired (ADR 0020). Ansible content returns with the baseline role.

See [`tofu/README.md`](./tofu/README.md) for the execution guide.
