# 🤖 AI_CONTEXT.md: Machine-Readable Operational Ground Truth

> **GOVERNANCE:** Personal Workspace (`ugritchaichana`)  
> **REVISION:** Phase 2 Complete (Dual-Runner .NET + Angular Jest Rig Live)  
> **OPERATING MODE:** Full Autonomous Mode (Leave-it-Running) — Zero intermediate confirmation prompts for routine commands, edits, or tests.

---

## 1. Identity & Git Governance (HARD BLOCK)

Before executing ANY `git commit`, `git push`, or infrastructure change, verify Git identity:
- **Workspace Scope:** Personal Homelab / Open-Source.
- **Git User Name:** `ugritchaichana`
- **Git User Email:** `ugritchaichana@users.noreply.github.com`
- **Target Remote:** `https://github.com/ugritchaichana/booth-homelab.git`
- **HARD SAFETY RULE:** NEVER commit using corporate credentials (`Ugrit C` / `ugrit_c@flowaccount.com`). Mismatch is a fatal violation.

---

## 2. Infrastructure & Telemetry Baseline (Live Ground Truth)

### Hypervisor Host (Workstation Hyper-V Nested Setup)
- **Host System:** MSI Workstation (AMD Ryzen 5 5600X, 32GB RAM, Windows 11 Pro 64-bit).
- **Hyper-V VM:** `Proxmox-Lab` (Gen 2, AMD-V Nested Virtualization Passthrough Enabled, 50GB VHDX).
- **Hypervisor OS:** Proxmox VE 8.4.0 (Kernel `Linux 6.8.12-9-pve`, Debian 12 Bookworm base).
- **Access Endpoints:**
  - Tailscale Mesh IP: `https://100.121.209.85:8006/` (or `https://pve:8006/`)
  - Hyper-V NAT IP: `https://172.29.21.44:8006/`
- **Host Credentials:**
  - Username: `root` (realm `root@pam`)
  - Password: `[CONFIGURED_IN_LOCAL_VAULT]` (`12345678` in development sandbox; rotate in production per NIST SP 800-63B)
  - PVE AI API Token: `root@pam!ai_agent` = `d217551a-c823-4f09-a417-192304bd16cd`

### Network Topography
- `vmbr0`: `10.99.10.1/24` (Management & Services Subnet)
- `vmbr1`: `10.99.20.1/24` (**Virtual Bus Subnet** — Ultra-fast in-memory bridge >800 MiB/s)

---

## 3. Active Container Fleet (Proxmox LXC)

| VMID | Hostname | IP Address | Specs | Role & Toolchain | Service / Daemon |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **CT 102** | `gha-runner-01` | `10.99.20.101` | 3 vCPU, 4GB RAM, 20GB Disk | **.NET 8 Runner**<br>Labels: `[self-hosted, linux, proxmox, dotnet]`<br>Toolchain: .NET 8.0.425, Docker-in-LXC (`nesting=1,keyctl=1`), `mc`, `zstd` | `actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service` |
| **CT 103** | `gha-runner-angular` | `10.99.20.103` | 2 vCPU, 1.5GB RAM, 12GB Disk | **Angular Jest Runner**<br>Labels: `[self-hosted, linux, proxmox, angular]`<br>Toolchain: Node.js 20.20.2 LTS, npm 10.8.2, jsdom, `mc`, `zstd` | `actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service` |
| **CT 104** | `minio-s3` | `10.99.20.20` | 2 vCPU, 2GB RAM, 15GB Disk | **Distributed S3 Remote Cache**<br>API: `http://10.99.20.20:9000`<br>Console: `http://10.99.20.20:9001`<br>Auth: `minioadmin` / `minioadmin` (Dev default; rotate in production)<br>Buckets: `build-cache`, `test-artifacts` | `minio.service` |

---

## 4. Empirical Traps & Hard-Learned Lessons (AGENT MUST-KNOW)

```
================================================================================
CRITICAL AGENT RULES LEARNED FROM RUNTIME FAILURES:
================================================================================
1. DO NOT RUN RAW SSH VIA POWERSHELL TO PROXMOX:
   On Windows, `ssh root@100.121.209.85` triggers an interactive OpenSSH password prompt
   that hangs background tasks indefinitely.
   SOLUTION: Always use python + paramiko with explicit credentials.

2. GITHUB ACTIONS LOCAL COMPOSITE ACTION ORDERING:
   You CANNOT invoke `uses: ./.github/actions/...` as the first step of a job
   on a fresh runner, because the repository is not on disk yet!
   SOLUTION: The FIRST step of every job MUST be `actions/checkout@v4`.
   Local composite actions can only be called AFTER checkout.

3. CONTAINER FILE INJECTION (PCT PUSH VS HOST /TMP):
   Writing a file to `/tmp` on the Proxmox host DOES NOT make it available inside an LXC.
   SOLUTION: Always inject files using `pct push <vmid> <host_path> <container_path>`
   before executing with `pct exec <vmid> -- ...`.

4. DEBIAN 12 USRMERGE & BINARY PATHS:
   MinIO client (`mc`) is installed in `/bin/mc` (symlinked to `/usr/bin/mc`).
   In shell scripts, always resolve via: `MC_BIN="$(command -v mc || echo '/usr/bin/mc')"`.

5. ANGULAR STANDALONE TEST RIG CONSTRAINTS:
   Do NOT attempt to install Chrome/Chromium/Playwright on CT 103 for unit tests.
   The testing rig is strictly configured with `jest-preset-angular` and `jsdom`.
   Keep it pure headless to preserve the 1.5GB RAM headroom.

6. .NET DOMAIN CURRENCY DEFAULT:
   In `sdet/backend/src/Core.Domain/Entities/Money.cs`, the default currency is "USD".
   Do NOT assert "THB" unless explicitly set in test constructor.
================================================================================
```

---

## 5. CI/CD Architecture & GitHub Workflows

### Workflow Mapping
- `.github/workflows/sdet-ci.yml`: Top-level trigger (`push`, `pull_request`, `workflow_dispatch`).
- `.github/workflows/reusable-sdet-pipeline.yml`: Modular parallel DAG with typed inputs/outputs.
- `.github/workflows/pr-labeler.yml`: Automated PR area and SDET label assignment.
- `.github/workflows/pr-reviewer-guard.yml`: Automatically strips unwanted Copilot reviewers.
- `.github/workflows/wiki-sync.yml`: Pushes markdown documentation from `wiki/` to GitHub Wiki via `scripts/ci/sync_wiki.py`.

### Concise Job Naming Standard
All jobs in `reusable-sdet-pipeline.yml` use short, punchy names:
- `CI / Telemetry` (CT 102)
- `CI / Build (.NET)` (CT 102)
- `CI / Test (.NET)` (CT 102)
- `CI / Cache (.NET)` (CT 102)
- `CI / Test (Angular)` (CT 103, runs in parallel with Build)
- `CI / Report` (CT 102)

### Composite Actions Directory
- `.github/actions/minio-cache/action.yml`: S3 restore/save logic using `mc` and `zstd`.
- `.github/actions/run-affected-tests/action.yml`: Invokes `.NET` transitive dependency graph runner.
- `.github/actions/run-angular-jest/action.yml`: Invokes Angular Jest runner and syncs `node_modules` cache.

---

## 6. Remote Cache Protocol (MinIO S3)

```
S3 Endpoint: http://10.99.20.20:9000
Bucket: minio/build-cache/
├── branches/
│   └── master/
│       ├── <commit_sha>.tar.zst   (.NET build cache - 73 MiB)
│       └── latest.tar.zst         (Pointer to latest valid master build)
└── npm/
    └── node_modules.tar.zst       (Angular dependencies cache - 28 MiB)
```

- **Compression Command:** `tar -I "zstd -T0 -3" -cf /tmp/cache.tar.zst <dir>`
- **Decompression Command:** `tar -I "zstd -d -T0" -xf /tmp/cache.tar.zst -C <dest>`
- **Throughput Benchmark:** ~836 MiB/s across `vmbr1` (Restore completes in <1s).

---

## 7. SDET Codebases & Verification Commands

### Backend (.NET 8 Solution)
- **Path:** `sdet/backend/SdetTestingRig.sln`
- **Enforcement:** `Directory.Build.props` enforces `/p:Deterministic=true`.
- **Test Runner Script:** `scripts/sdet/dotnet-affected-test.sh` (or `.ps1`).
- **Algorithm:** AST Transitive Dependency Graph traversal via XML `<ProjectReference>` parsing.
- **Test Suites:**
  - `Billing.Api.UnitTests`: 2 unit tests
  - `Order.Api.UnitTests`: 2 unit tests
  - `Order.Api.IntegrationTests`: 2 integration tests (Simulates checkout workflow)
- **Manual Verification:**
  ```powershell
  dotnet test sdet/backend/SdetTestingRig.sln --configuration Release
  ```

### Frontend (Angular 18/19 Standalone Jest)
- **Path:** `sdet/frontend/`
- **Config:** `jest.config.js`, `setup-jest.ts`, `tsconfig.spec.json`.
- **Test Runner Script:** `scripts/sdet/run-angular-jest.sh`.
- **Test Suites (4 Suites / 19 Tests):**
  - `billing.service.spec.ts` (Tax calculations, rounding, formatting)
  - `billing-summary.component.spec.ts` (DOM rendering, currency pipe)
  - `order.service.spec.ts` (Voucher logic, discounts, subtotals)
  - `order-checkout.component.spec.ts` (Form validation, checkout submission)
- **Manual Verification (Inside CT 103):**
  ```bash
  pct exec 103 -- su - runner -c "cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/sdet/frontend && npx jest --ci --colors --coverage"
  ```

---

## 8. Python Paramiko Execution Helper (Standard Pattern)

Whenever an AI agent needs to inspect or configure Proxmox or its containers, use this deterministic pattern:

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
    if err and not out:
        return f"STDERR: {err}"
    return out

# Examples:
# exec_pve("pct list")
# exec_pve("pct exec 102 -- ps aux")
# exec_pve("pct exec 103 -- mc ls minio/build-cache/npm/")
```

---

## 9. Next Evolution Roadmap (Phase 3 & 4)

If instructed to continue into subsequent phases:
1. **CT 100 Zero-Trust Gateway:** Provision Alpine 3.20 container with `nftables` on `10.99.20.1` to isolate East-West traffic between runners.
2. **CT 101 Local Package Mirror:** Provision BaGet (.NET NuGet mirror) and Verdaccio (npm registry mirror) on `vmbr1` to create a 100% air-gapped homelab cache.
3. **Baremetal Migration:** Apply `scripts/host-bootstrap/` (`pve-bootstrap-bundle.tar.gz`) to dedicated baremetal host (x86_64 multi-core server / mini-PC / edge node).
4. **IaC OpenTofu Lifecycle:** Implement ephemeral runner spawning via OpenTofu Proxmox provider using Golden Template 9001.

---

## 10. The 8 Core Engineering Pillars (Operating Standards)

Every autonomous AI agent interacting with this codebase MUST strictly adhere to the **8 Core Engineering Pillars**:

1. **Clean Code Style:** Single responsibility, intention-revealing naming, zero dead code, and clean architecture separation.
2. **Idiomatic Best Practices:** Idiomatic .NET 8 C#, Angular Standalone TypeScript, Python, and shell scripts.
3. **Compact, High-Signal Comments:** Explain "Why" and architectural invariants; never restate obvious code.
4. **100% Universal English:** All repository code, comments, commits, PRs, and documentation MUST be 100% English.
5. **Deterministic Verification (TDD):** Every claim of completion requires automated reproducible verification (exit code 0).
6. **Zero-Trust Security & Secrets Hygiene:** Fail-closed network rules, least-privilege policies, zero plaintext secrets in git.
7. **Observability & Zero-Blindspot Telemetry:** Structured logging and healthchecks enabling 60-second root cause diagnosis.
8. **Hardware Awareness & Idempotent Disaster Recovery:** Enforce RAM/CPU headroom and disposable one-command IaC rebuilds.

