# Ansible Configuration Management & Idempotent Orchestration

Declarative, idempotent configuration management for the Booth Homelab infrastructure, managing hypervisor host network isolation, MinIO S3 caching appliances, and self-hosted GitHub Actions runners.

---

## 🏗️ Directory Layout

```
iac/ansible/
├── ansible.cfg                # Optimized settings (pipelining, 10 forks, yaml stdout)
├── inventory/
│   ├── hosts.ini              # Host topology & VMID mappings
│   └── group_vars/
│       ├── all.yml            # Universal subnets, ports, gateway
│       ├── ci_runners.yml     # Runner utilities, versions, mc binary
│       └── s3_cache.yml       # MinIO credentials, bucket policies
├── playbooks/
│   ├── site.yml               # Master orchestration playbook
│   ├── 01-host-setup.yml      # Zero-trust bridge isolation & netfilter rules
│   ├── 02-cache-storage.yml   # MinIO S3 service & bucket init
│   └── 03-runners.yml         # .NET 8 & Angular runners configuration
└── roles/
    ├── common/                # Base utilities (zstd, git, sudo, runner user)
    ├── enterprise_firewall/   # Netfilter HOMELAB-FORWARD chain & L2 isolation
    │   └── templates/         # homelab-firewall.j2 (parameterized netfilter)
    ├── minio_cache/           # Alpine OpenRC service & anonymous policy
    │   └── templates/         # minio.env.j2, minio.initd.j2
    ├── proxmox_host/          # LXC appliance template manager (pveam download)
    ├── runner_dotnet/         # CT 102 (.NET 8 SDK, Docker-in-LXC)
    └── runner_angular/        # CT 103 (Node.js 20 LTS, Jest headless jsdom)
```

---

## 🚀 Execution Guide

### 1. Test Connectivity / Ping
```bash
ansible -i inventory/hosts.ini all -m ping
```

### 2. Full Site Orchestration
```bash
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

### 3. Targeted Playbook Execution
```bash
# Apply Zero-Trust Firewall only:
ansible-playbook -i inventory/hosts.ini playbooks/01-host-setup.yml

# Reconfigure MinIO Cache only:
ansible-playbook -i inventory/hosts.ini playbooks/02-cache-storage.yml

# Provision CI Runners only:
ansible-playbook -i inventory/hosts.ini playbooks/03-runners.yml
```
