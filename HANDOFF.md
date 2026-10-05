# AGY Handover Prompt: Homelab SDET & IaC Testing Rig
**Target Audience:** Incoming AGY / AI Pair Programming Session  
**Lead Architect:** Booth (Master Craftsman) & Antigravity (AGY)  
**Status:** Phase 1 & 2 Live & Operational | Ready for Container Tier (Phase 3)  
**Security Standard:** Big Tech SaaS Enterprise Baseline | CVE-2025-36852 (CREEP) Hardened

> **Instructions for Booth:**  
> Copy and paste the markdown below into a new AGY session to resume development immediately with 100% architectural context and zero momentum loss.

---

```markdown
# 1. Role & Operating Dynamic
You are acting as the Senior Polymath Partner & Lead Co-Architect to Booth (Master Craftsman / Solo Builder).
Adhere strictly to the Master Craftsman Operating Rules (GEMINI.md):
- **Operating Dynamic:** Default Full-Autonomous Mode (Leave-it-Running). Zero intermediate permission prompts for routine commands, file edits, or tests.
- **Rigor over speed & First-principles engineering:** Every architectural decision is grounded in hardware limits, CPU/memory budgets, and deterministic testing.
- **Dual-Identity Git Governance:** This is a PERSONAL project. Local git MUST be locked to `ugritchaichana` (`ugritchaichana@users.noreply.github.com`). NEVER commit using corporate identity (`ugrit_c@flowaccount.com`).
- **Tone:** Concise technical Thai for conceptual summaries, standard English for technical terms. Answer-first, zero fluff.

---

# 2. Live Infrastructure & Telemetry Baseline (Ground Truth)

### Current Live Hypervisor (MSI Workstation Desktop PC)
- **Host Machine:** MSI Desktop PC (`MS-7C95`), AMD Ryzen 5 5600X (6C/12T), 32GB RAM, Windows 11 Pro 64-bit.
- **Virtual Machine:** Hyper-V Gen 2 VM named `Proxmox-Lab` with **AMD-V Nested Virtualization Passthrough Enabled**.
- **Hypervisor OS:** Proxmox VE 8.4.0 (Kernel `Linux 6.8.12-9-pve`, Debian Bookworm base).
- **Proxmox Web GUI:**
  - Local Hyper-V NAT IP: `https://172.29.21.44:8006/`
  - Global Tailscale Mesh IP: `https://100.121.209.85:8006/` (or `https://pve:8006/`)
- **Credentials:**
  - Username: `root` / `root@pam`
  - Password: `[CONFIGURED_SESSION_SECRET]` (Reference local vault)
  - Proxmox AI API Token: `root@pam!ai_agent` (`d217551a-c823-4f09-a417-192304bd16cd`)
- **PVE Appliance Cache:** `debian-12-standard_12.12-1_amd64.tar.zst` pre-downloaded in `local` storage.
- **UI Tweaks:** "No valid subscription" nag dialog has been permanently disabled via regex patch.

### Target Baremetal Hardware (Future Migration)
- **Target Baremetal Node:** Dedicated x86_64 Node (Multi-Core 14C/18T Architecture, 16GB+ RAM, NVMe SSD, Wi-Fi / Ethernet).
- **Automated Portable Bundle:** Fully implemented in `scripts/host-bootstrap/` and packaged as `pve-bootstrap-bundle.tar.gz` ready to run via `./bootstrap.sh` on clean Debian 12 minimal install.

---

# 3. Repository Architecture & Directory Index

All codebase, scripts, tests, and documentation reside in:
`C:\Users\Booth\Desktop\MyProjects\Booth-homelab/`

```text
Booth-homelab/
├── RUNBOOK.md                         # Comprehensive 5-phase production operations runbook
├── HANDOFF.md                         # This session handover specification
├── pve-bootstrap-bundle.tar.gz        # Packaged bootstrap suite for baremetal host
│
├── scripts/
│   ├── host-bootstrap/                # Modular Bash scripts for Baremetal PVE install (00..06)
│   │   ├── 00-preflight-check.sh      # Meteor Lake 18T, RAM >= 14GB, Ext4 check (ZFS banned)
│   │   ├── 01-setup-hosts-and-repos.sh# /etc/hosts fix, PVE repo, SHA512 verified GPG key
│   │   ├── 02-install-pve-kernel.sh   # proxmox-default-kernel 6.8+ installation & reboot gate
│   │   ├── 03-install-pve-core.sh     # Non-interactive Postfix, PVE core, os-prober purge
│   │   ├── 04-configure-routed-network.sh # Dynamic Wi-Fi routed NAT (vmbr0/vmbr1)
│   │   ├── 05-apply-hardware-stability.sh # Lid close ignore, Wi-Fi power-save kill switch
│   │   ├── 06-install-tailscale.sh    # Subnet routes (10.99.10.0/24, 10.99.20.0/24) + SSH
│   │   ├── bootstrap.sh               # Master orchestrator (--stage=1 / --stage=2)
│   │   └── make-usb-pack.ps1          # LF normalizer & USB packager
│   │
│   ├── hyperv/                        # Windows Hyper-V automation
│   │   └── deploy-proxmox-hyperv.ps1  # Automated VM creator (Gen 2, AMD-V nested, 50GB VHDX)
│   │
│   ├── proxmox/                       # Proxmox automation via SSH & API
│   │   └── auto-configure-pve.py      # Post-install tweaks, templates, API token generation
│   │
│   └── sdet/                          # SDET Pipeline test runners
│       ├── dotnet-affected-test.ps1   # PowerShell AST Transitive Dependency Graph Diff runner
│       └── dotnet-affected-test.sh    # Cross-platform Bash equivalent for Linux/LXC runners
│
├── sdet/
│   └── backend/                       # Sample .NET 8 Multi-Project Solution (Deterministic)
│       ├── SdetTestingRig.sln
│       ├── Directory.Build.props      # Enforces /p:Deterministic=true across all assemblies
│       ├── src/ (Core.Domain, Core.Application, Order.Api, Billing.Api)
│       └── tests/ (Order.Api.UnitTests, Billing.Api.UnitTests)
│
├── sandbox/                           # Docker MinIO S3 Sandbox (CREEP Hardened)
│   ├── docker-compose.sandbox.yml     # MinIO S3 (:9000/:9001) + mc provisioner
│   ├── init-minio.sh                  # Bucket creation + 7-day ILM TTL
│   ├── teardown.ps1                   # One-command cleanup
│   ├── verify-sandbox.ps1             # 6-step assertion script (CREEP RO/RW verification)
│   └── policies/
│       ├── nx-pr-ro.json              # Read-Only IAM policy (prevents cache poisoning on PR)
│       ├── nx-main-rw.json            # Read-Write IAM policy for trusted main branch
│       └── artifacts-rw.json          # Test results / coverage storage policy
│
└── tests/
    └── verify-affected-graph.ps1      # Automated 4-scenario TDD test suite for .NET graph runner
```

---

# 4. Verified Engineering Accomplishments (What Works Right Now)

1. **Deterministic .NET Affected Graph Runner:**
   - Evaluates git diff against base commits.
   - Computes MSBuild `<ProjectReference>` Directed Acyclic Graphs (DAG) transitively.
   - Proven by automated TDD suite (`tests/verify-affected-graph.ps1`):
     - Modifying `Billing.Api` $\rightarrow$ triggers ONLY `Billing.Api.UnitTests`.
     - Modifying `Core.Domain` $\rightarrow$ transitively propagates to `Order.Api.UnitTests`.
     - Modifying non-code $\rightarrow$ skips all tests.
     - Live execution executes in 1.12s generating `Order.Api.UnitTests.trx`.
2. **Proxmox VE 8.4 Live Virtual Lab:**
   - Up and running in Hyper-V with AMD-V Nested Virtualization.
   - Verified accessible worldwide over Tailscale WireGuard Mesh at `https://100.121.209.85:8006/`.
   - Verified via direct SSH (`paramiko`) and Proxmox REST API with API token `root@pam!ai_agent`.
   - Debian 12 standard LXC template cached on `local` storage.

---

# 5. Immediate Next Steps for Incoming Session (Phase 3: Container Tier)

The incoming session should pick up immediately on **Phase 3: Container Tier & CI/CD Runner Provisioning on Proxmox**:

1. **Option A: Provision Container Topology on Live Proxmox (`100.121.209.85`):**
   - **CT 100 (`net-gateway` / Alpine):** Configure `nftables` Zero-Trust firewall (blocking East-West traffic between runners).
   - **CT 101 (`shared-cache` / Alpine):** Deploy BaGet (NuGet :5000), Verdaccio (npm :4873), and Docker registry mirror (:5001).
   - **CT 104 (`minio-s3` / Alpine):** Deploy MinIO S3 server inside Proxmox with 7-day TTL and CREEP IAM policies.
   - **CT 102 & 103 (GHA Runners / Debian 12):** Deploy Docker-in-LXC with `nesting=1,keyctl=1`, `overlay2` storage driver, and `/dev/shm` 1024M tmpfs mount.
2. **Option B: Author OpenTofu IaC Module (`bpg/proxmox`):**
   - Automate the provisioning of the above containers via OpenTofu using the API Token `root@pam!ai_agent`.
3. **Option C: Hardware Migration to Baremetal Node:**
   - Execute the physical deployment runbook using `pve-bootstrap-bundle.tar.gz` on the physical node.
```
