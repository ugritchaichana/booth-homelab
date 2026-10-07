# Infrastructure as Code

This directory holds the declarative provisioning and configuration code for the lab.

| Path | Purpose |
| :--- | :--- |
| [`tofu/`](./tofu/) | OpenTofu configuration for Proxmox objects, plus the instance flavor catalog (`tofu/flavors.json`). |
| [`ansible/`](./ansible/) | Ansible playbooks and roles for the operating system and services inside each machine. |
| [`proxmox/`](./proxmox/) | Answer-file template for the unattended Proxmox VE install. |
| [`secrets/`](./secrets/) | SOPS-encrypted host secrets. |

The bootstrap scripts and the cache policies of the previous host were retired (ADR 0020). The Ansible content is retired in the next change and rebuilt for the current host.

See [`tofu/README.md`](./tofu/README.md) and [`ansible/README.md`](./ansible/README.md) for execution guides.
