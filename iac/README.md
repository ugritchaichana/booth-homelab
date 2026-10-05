# Infrastructure as Code (IaC) Architecture

Welcome to the **Booth-homelab** Infrastructure as Code (IaC) directory. This directory provides declarative provisioning, idempotent configuration management, and baremetal bootstrapping for our continuous testing infrastructure.

---

## 🏛️ Architecture Overview

The infrastructure stack is strictly decoupled into three layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                          iac/ (Infrastructure as Code)                 │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. iac/tofu/          Declarative Compute & Network Provisioning      │
│                        - OpenTofu / Terraform with bpg/proxmox (~> 0.68)│
│                        - Multi-Cloud Flavor Catalog (AWS, GCP, Azure,  │
│                          Hetzner, DigitalOcean)                        │
│                        - Manages CT 102, CT 103, CT 104 lifecycles     │
│                                                                        │
│  2. iac/ansible/       Idempotent OS & Service Configuration           │
│                        - Ansible Playbooks & Modular Roles             │
│                        - Zero-Trust Netfilter & L2 Bridge Port Isolation│
│                        - MinIO S3 Remote Cache & Anonymous Policies    │
│                        - .NET 8 / Docker & Angular Jest Runner stacks  │
│                                                                        │
│  3. iac/bootstrap/     Baremetal Host Bootstrapping                    │
│                        - Debian 12 to Proxmox VE 8.4 transformation    │
│                        - Kernel 6.8.12-9-pve & Tailscale mesh setup    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

---

## ⚡ Quick Navigation

| Component | Path | Primary Technology | Purpose |
| :--- | :--- | :--- | :--- |
| **Compute & Topology** | [`iac/tofu/`](./tofu/) | OpenTofu / Terraform (`bpg/proxmox`) | Provision LXC containers, network interfaces, and storage disks with multi-cloud flavor sizing. |
| **Configuration** | [`iac/ansible/`](./ansible/) | Ansible (`playbooks/site.yml`) | Configure runners, install SDKs, enforce firewalls, and initialize S3 bucket policies. |
| **Host Bootstrap** | [`iac/bootstrap/`](./bootstrap/) | POSIX Bash Scripts (`bootstrap.sh`) | Baremetal Debian-to-PVE conversion and Tailscale mesh join. |

---

## 🌐 Multi-Cloud Instance Flavor Catalog

Tired of hardcoded RAM and CPU numbers? Our OpenTofu provisioning engine exposes a public cloud flavor catalog ([`iac/tofu/flavors.json`](./tofu/flavors.json)):

```bash
# Provision using AWS instance flavor:
tofu apply -var="cloud_provider=aws" -var="runner_dotnet_flavor=t3.medium"

# Provision using Hetzner Cloud instance flavor:
tofu apply -var="cloud_provider=hetzner" -var="runner_dotnet_flavor=cx22"
```

Refer to [`iac/tofu/README.md`](./tofu/README.md) and [`iac/ansible/README.md`](./ansible/README.md) for full execution guides.
