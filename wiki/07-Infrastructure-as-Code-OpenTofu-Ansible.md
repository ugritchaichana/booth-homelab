# 07. Infrastructure as Code (OpenTofu & Ansible)

## 1. Overview & Architecture

The **Booth-homelab** infrastructure is managed entirely through industry-standard declarative Infrastructure-as-Code (IaC) and configuration management:

1. **OpenTofu / Terraform (`iac/tofu/`):**
   - Uses the modern `bpg/proxmox` provider (`~> 0.68.0`) to provision compute (LXC containers), network bridges, and storage volumes.
   - Features a **Multi-Cloud Instance Flavor Catalog** (`flavors.json`) that abstracts hardware sizing to popular cloud VM tiers (AWS, GCP, Azure, Hetzner, DigitalOcean).
2. **Ansible (`iac/ansible/`):**
   - Manages idempotent OS configuration, software runtimes (.NET 8 SDK, Node.js 20 LTS, Docker), MinIO S3 caching daemon, and netfilter zero-trust firewalling.
3. **Baremetal Bootstrapping (`iac/bootstrap/`):**
   - Host transformation scripts converting minimal Debian 12 Bookworm into Proxmox VE 8.4 with kernel `6.8.12-9-pve` and Tailscale mesh.

---

## 2. Multi-Cloud Instance Flavor Catalog

Instead of hardcoding memory and CPU allocations, OpenTofu maps public cloud instance tiers to Proxmox VE resources:

```hcl
# Select cloud provider catalog and instance flavors
cloud_provider        = "aws"
runner_dotnet_flavor  = "t3.medium"  # 2 vCPU, 4096 MiB RAM, 30 GB Disk
runner_angular_flavor = "t3.small"   # 2 vCPU, 2048 MiB RAM, 20 GB Disk
minio_cache_flavor    = "t3.small"   # 2 vCPU, 2048 MiB RAM, 20 GB Disk
```

### Supported Providers:
- **AWS:** `t3.nano` to `t3.xlarge`, `c5.large`, `m5.large`
- **GCP:** `e2-micro` to `e2-standard-4`, `c2-standard-4`
- **Azure:** `Standard_B1s` to `Standard_D4s_v5`, `Standard_F2s_v2`
- **Hetzner Cloud:** `cx22`, `cx32`, `cx42`, `cpx21`, `cpx31`
- **DigitalOcean:** `s-1vcpu-1gb` to `s-2vcpu-4gb`, `c-2`, `c-4`

---

## 3. OpenTofu Provisioning Workflow

```bash
cd iac/tofu

# Initialize provider plugins
tofu init

# Plan deployment with AWS flavors
tofu plan -var="cloud_provider=aws" -var="runner_dotnet_flavor=t3.medium"

# Apply changes
tofu apply -auto-approve
```

---

## 4. Ansible Configuration Management Workflow

```bash
cd iac/ansible

# Test connectivity to all managed nodes
ansible -i inventory/hosts.ini all -m ping

# Execute master orchestration playbook
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```
