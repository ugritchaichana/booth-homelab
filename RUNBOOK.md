# Production RunBook: Homelab SDET & IaC Testing Rig

**Standard:** Big Tech SaaS Continuous Testing Standard  
**Lead Architects:** Booth (`ugritchaichana`) & Antigravity (Lead AI Co-Architect)  
**Revision:** Phase 2 Complete (Dual-Runner .NET 8 + Angular Jest Rig Live)  
**Target Environments:**
- **Environment A (Live Active Rig):** Windows 11 Workstation / AMD Ryzen 5 5600X / 32GB RAM / Hyper-V Nested Proxmox VE 8.4.0
- **Environment B (Target Baremetal Rig):** Dedicated x86_64 Node (Multi-Core 14C/18T Architecture / 16GB+ RAM / Wi-Fi & Ethernet)  
**Network Topography:** Restricted Network / CGNAT $\rightarrow$ Tailscale WireGuard Mesh $\rightarrow$ In-Memory Virtual Bus (`vmbr1`)

---

## Table of Contents

1. [Executive Architecture & Dual-Environment Matrix](#1-executive-architecture--dual-environment-matrix)
2. [Environment A Operations: Live Workstation Hyper-V & Nested Proxmox](#2-environment-a-operations-live-workstation-hyper-v--nested-proxmox)
3. [Environment B Operations: Baremetal Bootstrapping (Dedicated Node)](#3-environment-b-operations-baremetal-bootstrapping-dedicated-node)
4. [Container Fleet Architecture & Runner Lifecycle](#4-container-fleet-architecture--runner-lifecycle)
5. [MinIO S3 Remote Cache Administration & Disaster Recovery (CT 104)](#5-minio-s3-remote-cache-administration--disaster-recovery-ct-104)
   - [5.1 Bucket Hierarchy & TTL Policies](#51-bucket-hierarchy--ttl-policies)
   - [5.2 Disaster Recovery & Bucket Re-initialization SOP](#52-disaster-recovery--bucket-re-initialization-sop)
   - [5.3 Cache Purge for Cold Build Benchmarking](#53-cache-purge-for-cold-build-benchmarking)
   - [5.4 Enterprise Credential Hardening & Rotation SOP](#54-enterprise-credential-hardening--rotation-sop)
   - [5.5 Enterprise Password Complexity Standards (NIST SP 800-63B / CIS)](#55-enterprise-password-complexity-standards-nist-sp-800-63b--cis)
6. [CI/CD Pipeline Integration & GitHub Workflows](#6-cicd-pipeline-integration--github-workflows)
7. [Ephemeral Runner Lifecycle & Zero-Trace Decommissioning (IaC)](#7-ephemeral-runner-lifecycle--zero-trace-decommissioning-iac)
8. [Troubleshooting, Empirical Traps & Incident Decision Trees](#8-troubleshooting-empirical-traps--incident-decision-trees)

---

## 1. Executive Architecture & Dual-Environment Matrix

The Homelab architecture is engineered for seamless operation across two complementary environments, sharing identical container configurations, CI/CD pipelines, and remote caching layers:

### Dual-Environment Comparison Matrix

| Dimension | Environment A (Live Active Workstation) | Environment B (Target Baremetal Node) |
| :--- | :--- | :--- |
| **Primary Role** | Active Dev/Test & Autonomous Verification Rig | Dedicated Standalone SDET Homelab Server |
| **Host Hardware** | AMD Ryzen 5 5600X (6C/12T), 32 GB DDR4 | Modern Multi-Core x86_64 Node (14C/18T Hybrid), 16 GB+ RAM |
| **Hypervisor Layer** | Windows 11 Pro Hyper-V (Gen 2 VM: `Proxmox-Lab`) | Proxmox VE 8.4 Baremetal on Debian 12 Minimal |
| **Virtualization Mode** | Nested AMD-V Virtualization Passthrough | Baremetal KVM / Kernel 6.8+ Enterprise Stack |
| **Network Uplink** | Hyper-V Internal NAT Switch (`172.29.16.1/20`) | Wi-Fi / Ethernet Adapter via Routed NAT |
| **Mesh Access** | Tailscale Mesh IP: `100.121.209.85:8006` | Tailscale Mesh IP (Subnet Router `10.99.10.0/24`) |
| **Internal Bridges** | `vmbr0` (`10.99.10.1`), `vmbr1` (`10.99.20.1`) | `vmbr0` (`10.99.10.1`), `vmbr1` (`10.99.20.1`) |
| **Storage Subsystem** | 50 GB VHDX (Ext4 LVM-Thin) | 512 GB PCIe Gen4 NVMe (Ext4 LVM-Thin — ZFS Banned) |

### Internal Network Topography

```
[ Tailscale Mesh / LAN Clients ]
               │
               ▼ (Port 8006 / SSH / Port 9001 Console)
   ┌────────────────────────────────────────────────────────┐
   │ Proxmox VE Host (Hyper-V VM or Baremetal Node)         │
   │ Host IP: 100.121.209.85 (Tailscale) / 172.29.21.44     │
   ├────────────────────────────────────────────────────────┤
   │ Management Subnet: vmbr0 (10.99.10.1/24)               │
   │ Virtual Bus Subnet: vmbr1 (10.99.20.1/24)              │
   │                                                        │
   │  ┌─────────────────┐ ┌─────────────────┐ ┌──────────┐ │
   │  │ CT 102          │ │ CT 103          │ │ CT 104   │ │
   │  │ gha-runner-01   │ │ gha-runner-ang..│ │ minio-s3 │ │
   │  │ (.NET 8 Runner) │ │ (Angular Jest)  │ │ (Cache)  │ │
   │  │ 10.99.20.101    │ │ 10.99.20.103    │ │ 10.99.20.20│
   │  └────────┬────────┘ └────────┬────────┘ └────▲─────┘ │
   │           │                   │               │       │
   │           └───────────────────┴───────────────┘       │
   │              Fast In-Memory Cache I/O (>800 MiB/s)    │
   └────────────────────────────────────────────────────────┘
```

---

## 2. Environment A Operations: Live Workstation Hyper-V & Nested Proxmox

Used for controlling, managing, and recovering the hypervisor host on the active Windows 11 workstation:

### 2.1 Hyper-V VM Lifecycle Commands (PowerShell Administrator)

```powershell
# 1. Check VM status
Get-VM "Proxmox-Lab"

# 2. Start hypervisor VM
Start-VM "Proxmox-Lab"

# 3. Save VM state for fast suspension
Save-VM "Proxmox-Lab"

# 4. Stop Proxmox gracefully
Stop-VM "Proxmox-Lab"

# 5. Verify Nested AMD-V Virtualization (must always be True)
Get-VMProcessor "Proxmox-Lab" | Select-Object VMName, ExposeVirtualizationExtensions

# 6. Enable Nested Virtualization if disabled
Set-VMProcessor -VMName "Proxmox-Lab" -ExposeVirtualizationExtensions $true

# 7. Verify and enable MAC Address Spoofing (required for virtual bridges vmbr0/vmbr1)
Get-VMNetworkAdapter "Proxmox-Lab" | Set-VMNetworkAdapter -MacAddressSpoofing On
```

### 2.2 Host Endpoint Access

- **Proxmox Web GUI:**
  - Via Tailscale Mesh: `https://100.121.209.85:8006/`
  - Via Hyper-V Internal NAT: `https://172.29.21.44:8006/`
- **MinIO Web Console:**
  - Via Tailscale Mesh: `http://100.121.209.85:9001/`
  - Via Hyper-V Internal NAT: `http://172.29.21.44:9001/`
- **Host Credentials:**
  - Username: `root` (Realm: `root@pam`)
  - Password: `[LOCAL_VAULT]` (`12345678` in development sandbox)
  - PVE AI API Token ID: `root@pam!ai_agent`
  - PVE AI API Token Secret: `d217551a-c823-4f09-a417-192304bd16cd`

> [!WARNING]
> **Host Credential Rotation Advisory:**  
> The password `12345678` is strictly for isolated local development sandboxes. For any shared, staging, or production baremetal host, run `passwd root` immediately during provisioning to set a secure password meeting the [Section 5.5 Enterprise Password Complexity Standards](#55-enterprise-password-complexity-standards-nist-sp-800-63b--cis).

### 2.3 Non-Interactive Host Execution via Python Paramiko

> [!IMPORTANT]
> **DO NOT run `ssh root@100.121.209.85` directly in Windows PowerShell:** The command hangs indefinitely on an interactive password prompt.  
> Always use Python Paramiko for deterministic, non-interactive execution:

```python
import paramiko

def exec_pve(cmd: str) -> str:
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect('100.121.209.85', username='root', password='[LOCAL_VAULT_PW]')
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='ignore')
    err = stderr.read().decode('utf-8', errors='ignore')
    ssh.close()
    return out if out else f"STDERR: {err}"

# Usage examples:
# print(exec_pve("pct list"))
# print(exec_pve("pct status 102"))
```

---

## 3. Environment B Operations: Baremetal Bootstrapping (Dedicated Node)

Used when migrating and bootstrapping the infrastructure onto a dedicated baremetal host node (e.g. x86_64 Mini-PC or Server Node with 16GB+ RAM):

### Step 3.1: Prepare Bootable USB & Bootstrap Bundle

```powershell
# 1. Run .NET Transitive Dependency Graph verification before packaging
powershell -ExecutionPolicy Bypass -File tests/verify-affected-graph.ps1

# 2. Package bootstrap bundle to USB drive (auto-converts line endings to LF)
powershell -ExecutionPolicy Bypass -File scripts/host-bootstrap/make-usb-pack.ps1 -TargetUsbDrive "E:\"
```
Resulting archive on USB: `pve-bootstrap-bundle.tar.gz`

### Step 3.2: Install Debian 12 Minimal on Baremetal Node

1. Create a Debian 12 Netinst bootable USB using Rufus (select **DD Image** mode).
2. Enter BIOS (press `F2` or `Del` at power-on):
   - **Disable Secure Boot** (Critical: prevents Proxmox kernel `bad shim signature` boot halts).
   - Set Function Key Behavior to Standard.
3. Proceed with Debian 12 installation:
   - Connect Wi-Fi or Ethernet cable.
   - **Partitioning:** Select **Guided LVM (Ext4)** (*NEVER select ZFS to prevent ARC memory starvation on 16GB RAM*).
   - **Software Selection:** Uncheck all desktop environments; select ONLY **SSH server** and **standard system utilities** (No Desktop GUI).

### Step 3.3: Run Bootstrap Stage 1 (Pre-Reboot)

```bash
sudo -i
mkdir -p /mnt/usb
mount /dev/sdb1 /mnt/usb
cd /mnt/usb/host-bootstrap
chmod +x *.sh

# Execute Stage 1
./bootstrap.sh --stage=1
```

**Stage 1 Execution Scope:**
- `00-preflight-check.sh`: Verifies multi-core CPU threads, RAM $\ge 14\text{GB}$, Wi-Fi interface (`wlo1`), confirms non-ZFS filesystem.
- `01-setup-hosts-and-repos.sh`: Configures `/etc/hosts` pointing to `10.99.10.1`, adds PVE 8.x No-Subscription repo, fetches GPG key with checksum verification (`7da6fe34168...`), installs `firmware-iwlwifi`.
- `02-install-pve-kernel.sh`: Installs `proxmox-default-kernel` (Kernel 6.8+ for full hardware scheduler support) and updates GRUB.

### Step 3.4: Reboot and Run Bootstrap Stage 2 (Post-Reboot)

```bash
# Reboot into PVE Kernel
reboot

# After reboot, verify kernel version:
uname -r # Expected: 6.8.x-pve

# Execute Stage 2
cd /mnt/usb/host-bootstrap
./bootstrap.sh --stage=2
```

**Stage 2 Execution Scope:**
- `03-install-pve-core.sh`: Configures Postfix non-interactively, installs `proxmox-ve` and `chrony`, purges legacy Debian 6.1 kernel, removes `os-prober`.
- `04-configure-routed-network.sh`: Detects network interface (`wlo1`), writes Routed NAT configuration to `/etc/network/interfaces`, sets up IP forwarding and masquerading for `10.99.10.0/24` and `10.99.20.0/24`, and adds PREROUTING port forwards for MinIO S3 API (9000) and Web Console (9001).
- `05-apply-hardware-stability.sh`: Disables lid close suspension (`HandleLidSwitch=ignore`), installs persistent Wi-Fi power-save kill switch service (`wifi-powersave-off.service`), enables `net.ipv4.ip_forward = 1`.
- `06-install-tailscale.sh`: Installs Tailscale, connects to mesh network with advertised subnet routes and Tailscale SSH enabled.

---

## 4. Container Fleet Architecture & Runner Lifecycle

### 4.1 Active Container Fleet

| VMID | Hostname | IP Address | Resource Limit | Role & Toolchain | Systemd Service Daemon |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CT 102** | `gha-runner-01` | `10.99.20.101` | 3 vCPU / 4.0 GB RAM / 20 GB Disk | **.NET 8 CI Runner**<br>Labels: `[self-hosted, linux, proxmox, dotnet]`<br>Toolchain: .NET 8.0.425, Docker-in-LXC (`nesting=1,keyctl=1`), `mc`, `zstd` | `actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service` |
| **CT 103** | `gha-runner-angular` | `10.99.20.103` | 2 vCPU / 1.5 GB RAM / 12 GB Disk | **Angular Jest Runner**<br>Labels: `[self-hosted, linux, proxmox, angular]`<br>Toolchain: Node.js 20.20.2 LTS, npm 10.8.2, Pure Headless jsdom, `mc`, `zstd` | `actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service` |
| **CT 104** | `minio-s3` | `10.99.20.20` | 2 vCPU / 2.0 GB RAM / 15 GB Disk | **Distributed Remote Cache**<br>API: `:9000` / Console: `:9001`<br>Buckets: `build-cache`, `sdet-test-artifacts` | `minio.service` |

### 4.2 Runner Daemon Lifecycle Management

Execute these commands on the Proxmox Host via Paramiko or terminal console:

```bash
# 1. Check runner daemon service status
pct exec 102 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service --no-pager
pct exec 103 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service --no-pager

# 2. Restart runner daemons to flush stuck worker processes
pct exec 102 -- systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service
pct exec 103 -- systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service

# 3. Tail live runner logs
pct exec 102 -- journalctl -u actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service -n 50 --no-pager
```

### 4.3 Runner Token Rotation & Re-enrollment SOP

> [!NOTE]
> GitHub Registration Tokens expire after 60 minutes. If re-enrolling or recovering an offline runner:

```bash
# 1. Fetch fresh registration token via GitHub CLI
RUNNER_TOKEN=$(gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/ugritchaichana/booth-homelab/actions/runners/registration-token \
  --jq .token)
echo "Obtained token: $RUNNER_TOKEN"

# 2. Re-enroll CT 102 (.NET Runner):
pct exec 102 -- bash -c "
  cd /home/runner/actions-runner
  sudo ./svc.sh stop || true
  sudo ./svc.sh uninstall || true
  su - runner -c 'cd /home/runner/actions-runner && ./config.sh --url https://github.com/ugritchaichana/booth-homelab --token $RUNNER_TOKEN --name gha-runner-01 --labels self-hosted,linux,proxmox,dotnet --unattended --replace'
  sudo ./svc.sh install runner
  sudo ./svc.sh start
"

# 3. Re-enroll CT 103 (Angular Jest Runner):
pct exec 103 -- bash -c "
  cd /home/runner/actions-runner
  sudo ./svc.sh stop || true
  sudo ./svc.sh uninstall || true
  su - runner -c 'cd /home/runner/actions-runner && ./config.sh --url https://github.com/ugritchaichana/booth-homelab --token $RUNNER_TOKEN --name gha-runner-angular --labels self-hosted,linux,proxmox,angular --unattended --replace'
  sudo ./svc.sh install runner
  sudo ./svc.sh start
"
```

### 4.4 Direct In-Container Test Execution (Offline Manual Debugging)

Execute tests directly inside the containers without triggering GitHub Actions:

```bash
# Run .NET 8 Unit & Integration Tests in CT 102:
pct exec 102 -- su - runner -c "
  cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/sdet/backend
  dotnet test SdetTestingRig.sln --configuration Release --logger 'console;verbosity=normal'
"

# Run Angular Jest Standalone Tests in CT 103 (19 Tests / 4 Suites):
pct exec 103 -- su - runner -c "
  cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/sdet/frontend
  npx jest --ci --colors --coverage
"
```

---

## 5. MinIO S3 Remote Cache Administration & Disaster Recovery (CT 104)

### 5.1 Bucket Hierarchy & TTL Policies

```
minio/build-cache/
├── branches/
│   └── master/
│       ├── <commit_sha>.tar.zst   (.NET build cache - ~73 MiB)
│       └── latest.tar.zst         (Latest pointer for cache restoration)
└── npm/
    └── node_modules.tar.zst       (Angular dependencies cache - ~28 MiB)

minio/sdet-test-artifacts/
├── backend/<run_id>/              (.trx test reports & coverage)
└── frontend/<run_id>/             (Jest coverage reports)
```

### 5.2 Disaster Recovery & Bucket Re-initialization SOP

If CT 104 is reprovisioned or cache data is purged:

```bash
# 1. Verify MinIO Server is running
pct exec 104 -- rc-service minio status

# 2. Configure mc alias on host or runner (CT 102 / 103)
pct exec 102 -- mc alias set minio http://10.99.20.20:9000 minioadmin minioadmin

# 3. Create all required buckets
pct exec 102 -- mc mb -p minio/build-cache
pct exec 102 -- mc mb -p minio/sdet-test-artifacts

# 4. Set lifecycle policy to auto-expire files older than 7 days (prevents disk bloat)
pct exec 102 -- mc ilm rule add --expire-days 7 minio/build-cache
pct exec 102 -- mc ilm rule add --expire-days 7 minio/sdet-test-artifacts

# 5. Verify upload/download over vmbr1 Virtual Bus
pct exec 102 -- bash -c "
  echo 'healthcheck' > /tmp/hc.txt
  mc cp /tmp/hc.txt minio/build-cache/healthcheck.txt
  mc cp minio/build-cache/healthcheck.txt /tmp/hc-download.txt
  cat /tmp/hc-download.txt
  mc rm minio/build-cache/healthcheck.txt
"
```

### 5.3 Cache Purge for Cold Build Benchmarking

```bash
# Purge all .NET and npm caches:
pct exec 102 -- mc rm --recursive --force minio/build-cache/branches/master/
pct exec 102 -- mc rm --recursive --force minio/build-cache/npm/

# Verify bucket is empty:
pct exec 102 -- mc ls minio/build-cache/
```

### 5.4 Enterprise Credential Hardening & Rotation SOP

> [!WARNING]
> **Open-Source Default Credentials Disclaimer:**  
> The homelab configuration uses standard default credentials (`minioadmin` / `minioadmin` on CT 104, `root` / `12345678` on development Proxmox instances) strictly to facilitate turn-key open-source evaluation and deterministic test execution in isolated sandboxes.  
> **These defaults MUST be changed before exposing services to any shared network or production environment.**

#### Step 1: Rotate MinIO Root Administrative Credentials
To rotate root credentials on CT 104 (Alpine LXC):
```bash
# 1. Generate strong credentials adhering to the password standard
NEW_ROOT_USER="minio_admin_$(openssl rand -hex 4)"
NEW_ROOT_PASS="$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9!@#$%^&*()-_+=' | head -c 24)"

# 2. Update MinIO environment file on CT 104
pct exec 104 -- sh -c "cat <<EOF > /etc/conf.d/minio
MINIO_VOLUMES=\"/var/lib/minio/data\"
MINIO_OPTS=\"--address :9000 --console-address :9001\"
MINIO_ROOT_USER=\"$NEW_ROOT_USER\"
MINIO_ROOT_PASSWORD=\"$NEW_ROOT_PASS\"
EOF"

# 3. Restart MinIO service daemon
pct exec 104 -- rc-service minio restart

# 4. Update MinIO client alias on test runners (CT 102 and CT 103)
pct exec 102 -- mc alias set minio http://10.99.20.20:9000 "$NEW_ROOT_USER" "$NEW_ROOT_PASS"
pct exec 103 -- mc alias set minio http://10.99.20.20:9000 "$NEW_ROOT_USER" "$NEW_ROOT_PASS"
```

#### Step 2: Provision Granular IAM Service Accounts (Least Privilege)
Never distribute root administrative credentials to CI/CD runners. Instead, create scoped IAM Service Accounts:
```bash
# Create read-only service account for PR workflows
pct exec 102 -- mc admin user add minio sdet_pr_reader StrongPrReaderP@ss123!
pct exec 102 -- mc admin policy attach minio readonly --user sdet_pr_reader

# Create read-write service account for master pipeline
pct exec 102 -- mc admin user add minio sdet_ci_writer StrongCiWriterP@ss456!
pct exec 102 -- mc admin policy attach minio readwrite --user sdet_ci_writer
```

### 5.5 Enterprise Password Complexity Standards (NIST SP 800-63B / CIS)

All passwords, service keys, and access tokens used across the homelab infrastructure must comply with the following cryptographic and entropy standards:

| Criteria | Administrative / Root Accounts | CI/CD Service Accounts & API Keys |
| :--- | :--- | :--- |
| **Minimum Length** | **$\ge 20$ characters** | **$\ge 32$ characters** (or 256-bit entropy) |
| **Character Classes** | $\ge 4$ classes: `[A-Z]`, `[a-z]`, `[0-9]`, `[!@#$%^&*()-_+=[{]}\|:;,.<>?~]` | Cryptographically secure pseudo-random (`openssl rand -base64 32`) |
| **Banned Patterns** | Dictionary words, leetspeak (`P@ssw0rd`), sequential runs (`123456`, `qwerty`), project names (`booth`, `minio`, `proxmox`) | Shared secrets, hardcoded repository commits |
| **Rotation Cadence** | On team personnel change or suspected credential leak | 90 days or automated dynamic rotation |
| **Storage Standard** | Password vault / Secret manager (Bitwarden, Vault, KeePassXC) | GitHub Actions Encrypted Secrets / Environment Variables |

---

## 6. CI/CD Pipeline Integration & GitHub Workflows

### 6.1 Workflow Architecture & Job Graph

The CI/CD pipeline is structured as a modular DAG reusable dispatch action:
- `.github/workflows/sdet-ci.yml`: Entry point listening for `push`, `pull_request`, and `workflow_dispatch` events.
- `.github/workflows/reusable-sdet-pipeline.yml`: Core execution DAG structured into compact stages:

```mermaid
flowchart TD
    Start([Push / PR / Dispatch]) --> Telemetry["CI / Telemetry\n(CT 102)"]
    Telemetry --> BuildDotnet["CI / Build (.NET)\n(CT 102)"]
    Telemetry --> TestAngular["CI / Test (Angular)\n(CT 103 - Parallel)"]
    BuildDotnet --> TestDotnet["CI / Test (.NET)\n(CT 102)"]
    TestDotnet --> CacheDotnet["CI / Cache (.NET)\n(CT 102)"]
    CacheDotnet --> Report["CI / Report\n(CT 102)"]
    TestAngular --> Report
    Report --> End([Workflow Success])
```

### 6.2 Pipeline Control via GitHub CLI

```bash
# Trigger manual pipeline execution (Workflow Dispatch):
gh workflow run sdet-ci.yml --repo ugritchaichana/booth-homelab

# List 3 most recent pipeline runs:
gh run list --repo ugritchaichana/booth-homelab -L 3

# View latest run summary:
gh run view --repo ugritchaichana/booth-homelab

# Inspect detailed job logs:
gh run view <run_id> --job=<job_id> --log --repo ugritchaichana/booth-homelab
```

### 6.3 Automation Safeguards

- **PR Labeler (`.github/workflows/pr-labeler.yml`):** Automatically attaches labels (`backend`, `frontend`, `infrastructure`, `sdet`) based on modified paths.
- **Reviewer Guard (`.github/workflows/pr-reviewer-guard.yml`):** Automatically removes Copilot reviewers from PRs.
- **Wiki Auto-Sync (`.github/workflows/wiki-sync.yml`):** Automatically synchronizes `wiki/` documentation to GitHub Wiki on pushes to `master`.

---

## 7. Ephemeral Runner Lifecycle & Zero-Trace Decommissioning (IaC)

For Phase 3 ephemeral runner provisioning:

### 7.1 Golden Template Creation (Packer)

Run container sanitization before converting to a golden template:
```bash
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Convert to Golden Template:
pct template 9001
```

### 7.2 OpenTofu Ephemeral Runner Provisioning

```bash
cd iac/tofu
tofu init
tofu apply -auto-approve

# Test suite execution runs here...

# Destroy ephemeral runner immediately after test execution:
tofu destroy -auto-approve
```

### 7.3 Zero-Trace Decommissioning (Complete Host Reclamation)

When decommissioning the SDET rig to repurpose the host:

```bash
# 1. Backup Golden Template to external drive (Zstandard compressed)
mkdir -p /mnt/external_backup
mount /dev/sdX1 /mnt/external_backup
vzdump 9001 --compress zstd --dumpdir /mnt/external_backup/

# 2. Destroy containers and reclaim all storage
pct stop 102 && pct destroy 102
pct stop 103 && pct destroy 103
pct stop 104 && pct destroy 104
pct destroy 9001

# 3. Confirm clean storage status
pvesm status
```

---

## 8. Troubleshooting, Empirical Traps & Incident Decision Trees

### 8.1 The 6 Empirical Traps & Hard-Learned Solutions

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ THE 6 EMPIRICAL TRAPS & HARD-LEARNED SOLUTIONS                                  │
├──────────────────────────────────────────────────────────────────────────────────┤
│ 1. OPENSSH INTERACTIVE PROMPT HANG:                                              │
│    Windows PowerShell running 'ssh root@...' hangs on the password prompt.       │
│    --> Always use Python Paramiko with explicit credentials.                     │
│                                                                                  │
│ 2. COMPOSITE ACTION CHECKOUT ORDERING:                                           │
│    Do not invoke './.github/actions/...' before 'actions/checkout@v4'.           │
│    New runners do not have action YAML files on disk before checkout.            │
│    --> The first step of every job must always be actions/checkout@v4.           │
│                                                                                  │
│ 3. CONTAINER FILE INJECTION:                                                     │
│    Files in /tmp on Proxmox Host are not visible inside LXC containers.          │
│    --> Exclusively use 'pct push <vmid> <host_path> <container_path>'.           │
│                                                                                  │
│ 4. DEBIAN 12 USRMERGE BINARY PATH:                                               │
│    MinIO Client is at /bin/mc, which is a symlink to /usr/bin/mc.                │
│    --> Always resolve paths dynamically: $(command -v mc || echo '/usr/bin/mc') │
│                                                                                  │
│ 5. ANGULAR JEST PURE HEADLESS MEMORY CEILING:                                    │
│    Never install Chrome, Chromium, or Playwright inside CT 103.                  │
│    --> Use pure jsdom + jest-preset-angular to maintain a 1.5GB RAM ceiling.     │
│                                                                                  │
│ 6. .NET DOMAIN CURRENCY ASSERTION:                                               │
│    In Core.Domain, Money.Currency defaults to "USD", not "THB".                  │
│    --> Never assert "THB" unless explicitly passed to constructor.               │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Comprehensive Incident Response Decision Tree

```mermaid
flowchart TD
    Issue["Issue Detected in SDET Rig"] --> Triage{"What is the symptom?"}

    Triage -- "Runner Shows Offline on GitHub" --> R1["Check Container & Daemon Status"]
    R1 --> R2["Run: pct list\nAre CT 102/103 running?"]
    R2 -- "Stopped" --> R3["Run: pct start 102 && pct start 103"]
    R2 -- "Running" --> R4["Check: systemctl status actions.runner..."]
    R4 -- "Failed / Exited" --> R5["Fetch fresh token with 'gh api .../registration-token'\nRun Re-enroll SOP (Section 4.3)"]

    Triage -- "CI/CD Cache Miss Loop or Connection Refused" --> C1["Inspect MinIO (CT 104)"]
    C1 --> C2["Run: pct exec 104 -- rc-service minio status"]
    C2 -- "Down" --> C3["Run: pct exec 104 -- rc-service minio restart"]
    C2 -- "Up" --> C4["Test: pct exec 102 -- mc ls minio/build-cache/\nVerify alias and buckets exist (Section 5.2)"]

    Triage -- "Cannot Access Proxmox Web GUI :8006" --> N1["Verify Host Connectivity"]
    N1 --> N2{"Which Environment?"}`
    N2 -- "Env A (Workstation)" --> N3["Check Hyper-V: Get-VM 'Proxmox-Lab'\nIf stopped: Start-VM 'Proxmox-Lab'"]
    N2 -- "Env B (Baremetal Node)" --> N4["Check Wi-Fi Captive Portal & Sleep\nRun: systemctl status wifi-powersave-off"]
    N3 --> N5["Check Tailscale:\ntailscale status (Verify 100.121.209.85 is online)"]
    N4 --> N5

    Triage -- "System Sluggish / Linux OOM Warning" --> M1["Inspect RAM Headroom"]
    M1 --> M2["Run: free -h on Host"]
    M2 --> M3{"Is ZFS in Use?"}
    M3 -- "Yes" --> M4["Cap ZFS ARC:\necho 2147483648 > /sys/module/zfs/parameters/zfs_arc_max"]
    M3 -- "No" --> M5["Reduce CT 102 RAM cap or stop idle containers"]
```

---

*This RunBook has been verified and validated under Master Craftsman engineering standards, fully optimized for autonomous operations by both human operators and AI agents.*
