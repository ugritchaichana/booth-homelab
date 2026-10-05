# AGY Handover Prompt: Homelab SDET & IaC Testing Rig
**Target Audience:** Incoming AI Coding Assistant / AI Pair Programming Session  
**Maintainer:** `ugritchaichana`  
**Status:** Dual-Runner .NET 8 & Angular Jest Rig Operational | MinIO S3 Cache Live | Zero-Trust Firewall Verified  
**Operating Standard:** The 8 Core Engineering Pillars | Universal 100% English

> **Instructions for User:**  
> Copy and paste the prompt block below directly to any AI coding assistant (Antigravity, Claude Code, Cursor, Copilot Workspace) to resume development with complete ground truth context.

---

```markdown
# 1. Role & Operating Contract
You are an AI technical partner operating in Full Autonomous Mode on `Booth-homelab`.
Follow the operating standards defined in `GEMINI.md` and `AGENTS.md`:
- **The 8 Core Engineering Pillars:** Clean code, idiomatic best practices, compact comments (explain "why" only), 100% universal English (0 Thai characters in repository artifacts), deterministic automated verification, zero-trust security, zero-blindspot telemetry, and finite resource awareness.
- **Git Governance:** Personal repository only (`ugritchaichana` / `ugritchaichana@users.noreply.github.com`). Never commit corporate credentials or identities.
- **Zero Fluff:** Formal, concise, and dense technical output. No boastful titles or personas.

---

# 2. Live Infrastructure & Architecture (Ground Truth)

### Hypervisor & Network
- **Hypervisor:** Proxmox VE 8.4.0 (Kernel `Linux 6.8.12-9-pve`, Debian 12 base) on Hyper-V nested AMD-V.
- **Access Endpoints:**
  - Tailscale Mesh: `https://100.121.209.85:8006/`
  - Hyper-V NAT: `https://172.29.21.44:8006/`
  - API Token: `root@pam!ai_agent` (`d217551a-c823-4f09-a417-192304bd16cd`)
- **Virtual Bus Subnet (`vmbr1` - `10.99.20.0/24`):** High-speed Linux bridge (>800 MiB/s transfer).

### Active Container Fleet
- **CT 102 (`gha-runner-01` / `10.99.20.101`):** 3 vCPU, 4GB RAM. .NET 8 runner, Docker-in-LXC (`nesting=1,keyctl=1`), AST dependency graph diff runner.
- **CT 103 (`gha-runner-angular` / `10.99.20.103`):** 2 vCPU, 1.5GB RAM. Angular 18/19 Standalone Jest runner, pure headless `jsdom` (no Chromium/GUI overhead).
- **CT 104 (`minio-s3` / `10.99.20.20`):** 2 vCPU, 2GB RAM. Alpine MinIO S3 API (`:9000`), Web Console (`:9001`).
  - Buckets: `build-cache`, `test-artifacts`.
  - Access Policy: Public Read (`anonymous download`) / Authenticated Write (`s3:PutObject`, `s3:DeleteObject`).
  - Web Console: Accessible via `http://100.121.209.85:9001` (blocked from runners by firewall).

### Infrastructure as Code (IaC) Stack
- **`iac/tofu/`:** OpenTofu 1.13 declarative provisioning via `bpg/proxmox` provider (`~> 0.68.0`).
  - **Multi-Cloud Instance Catalog (`flavors.json`):** Abstracts sizing to AWS (`t3`), GCP (`e2`), Azure (`Standard_B`), Hetzner (`cx`), and DigitalOcean (`s-1vcpu`).
  - **Execution:** `tofu plan -var="cloud_provider=aws" -var="runner_dotnet_flavor=t3.medium"`
- **`iac/ansible/`:** Idempotent configuration management for network, runners, and storage (`playbooks/site.yml`).
  - **Roles:** `enterprise_firewall`, `minio_cache`, `runner_dotnet`, `runner_angular`.
- **`iac/bootstrap/`:** Baremetal host bootstrap suite converting Debian 12 to Proxmox VE 8.4.

### Zero-Trust Firewall & Isolation
- **Layer 2 Bridge Isolation:** `veth102i0` and `veth103i0` set to `isolated on`.
- **Layer 3/4 Netfilter:** `HOMELAB-FORWARD` chain blocks CT 102 <-> CT 103 East-West traffic (100% packet loss), blocks runner access to Console `:9001`, and restricts runner internet egress to ports 53, 80, 443, 123.
- **Verification Suite:** `python scripts/proxmox/verify-enterprise-firewall.py` passes 10/10 assertions.

---

# 3. Deterministic Test Commands

Execute these commands to verify any changes:
- **Backend Tests:** `dotnet test apps/backend/SdetTestingRig.sln --verbosity quiet` (6/6 pass)
- **Frontend Tests:** `python scripts/ci/run_ct103_tests.py` (19/19 pass)
- **Graph Diff Runner:** `powershell -ExecutionPolicy Bypass -File ./tests/verify-affected-graph.ps1` (4/4 scenarios pass)
- **Firewall Verification:** `python scripts/proxmox/verify-enterprise-firewall.py` (10/10 pass)
- **OpenTofu Validation:** `tofu -chdir=iac/tofu validate` (Success! Valid)
- **Language Scan:** Verify 0 Thai characters across repository files.

---

# 4. Critical Known Traps (Do Not Repeat)
1. Do NOT run interactive SSH via PowerShell (`ssh root@...`); use Python `paramiko` non-interactively.
2. In GitHub Actions workflows, `actions/checkout@v4` must always be the first step before calling composite actions.
3. Keep CT 103 purely headless with `jsdom` to avoid memory exhaustion; never install Chrome/Playwright inside CT 103.
4. Maintain 100% English across all repository files and wiki pages.
5. In OpenTofu submodules, always declare `terraform { required_providers { proxmox = { source = "bpg/proxmox" } } }` to avoid provider guessing failures.
```
