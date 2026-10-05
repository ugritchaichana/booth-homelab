# OpenTofu / Terraform Proxmox VE IaC Rig

Declarative Infrastructure-as-Code for provisioning self-hosted GitHub Actions CI runners and high-speed MinIO S3 caching appliances on Proxmox VE 8.4 using the modern `bpg/proxmox` provider.

---

## 🌟 Multi-Cloud Instance Flavor Catalog

Instead of hardcoding memory and vCPU numbers, this setup abstracts sizing using industry-standard public cloud VM tiers. OpenTofu ingests [`flavors.json`](./flavors.json) and translates cloud instance profiles directly into Proxmox hardware specifications.

### Supported Providers & Popular Profiles:
| Provider | Default Flavors | vCPU | RAM | Disk | Sizing Rationale |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **AWS** | `t3.nano` .. `t3.xlarge`, `c5.large`, `m5.large` | 2 - 4 | 0.5 - 16 GB | 10 - 80 GB | Burstable baseline for CI/CD |
| **GCP** | `e2-micro` .. `e2-standard-4`, `c2-standard-4` | 2 - 4 | 1 - 16 GB | 15 - 80 GB | Cost-efficient compute |
| **Azure** | `Standard_B1s` .. `Standard_D4s_v5` | 1 - 4 | 1 - 16 GB | 15 - 80 GB | Standard enterprise tiers |
| **Hetzner** | `cx22`, `cx32`, `cx42`, `cpx21`, `cpx31` | 2 - 8 | 4 - 16 GB | 40 - 160 GB | High-performance baremetal cloud |
| **DigitalOcean** | `s-1vcpu-1gb` .. `s-2vcpu-4gb`, `c-2`, `c-4` | 1 - 4 | 1 - 8 GB | 25 - 100 GB | Developer droplets |

---

## 🚀 Quickstart Execution

### 1. Initialize OpenTofu
```bash
tofu init
```

### 2. Plan Deployment
```bash
# Example 1: Using AWS Flavor Catalog
tofu plan -var="cloud_provider=aws" -var="runner_dotnet_flavor=t3.medium"

# Example 2: Using Hetzner Cloud Catalog
tofu plan -var="cloud_provider=hetzner" -var="runner_dotnet_flavor=cx22"
```

### 3. Apply Provisioning
```bash
tofu apply -auto-approve
```

---

## 📦 Provisioned Topology

| VMID | Hostname | OS / Engine | IP Address | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **102** | `gha-runner-01` | Debian 12 (Bookworm) | `10.99.20.101/24` | .NET 8 LTS, Docker-in-LXC (`nesting=1,keyctl=1`) |
| **103** | `gha-runner-angular` | Debian 12 (Bookworm) | `10.99.20.103/24` | Node.js 20 LTS, Angular Jest headless jsdom |
| **104** | `minio-s3` | Alpine Linux 3.23 | `10.99.20.20/24` | In-memory MinIO S3 cache (`:9000`), Console (`:9001`) |
