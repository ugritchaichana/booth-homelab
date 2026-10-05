# 🚀 Booth Homelab: Enterprise SDET & IaC Testing Rig

[![Release v1.0.0](https://img.shields.io/github/v/release/ugritchaichana/booth-homelab?color=blue&logo=github)](https://github.com/ugritchaichana/booth-homelab/releases/tag/v1.0.0)
[![SDET Homelab CI Pipeline](https://github.com/ugritchaichana/booth-homelab/actions/workflows/sdet-ci.yml/badge.svg)](https://github.com/ugritchaichana/booth-homelab/actions/workflows/sdet-ci.yml)
[![Synchronize Wiki Knowledge Base](https://github.com/ugritchaichana/booth-homelab/actions/workflows/wiki-sync.yml/badge.svg)](https://github.com/ugritchaichana/booth-homelab/actions/workflows/wiki-sync.yml)
[![Proxmox VE](https://img.shields.io/badge/Hypervisor-Proxmox%20VE%208.4-E57000?logo=proxmox&logoColor=white)](https://www.proxmox.com/)
[![Tailscale](https://img.shields.io/badge/Mesh%20VPN-Tailscale-24292E?logo=tailscale&logoColor=white)](https://tailscale.com/)
[![MinIO S3](https://img.shields.io/badge/Remote%20Cache-MinIO%20S3-C72C48?logo=minio&logoColor=white)](https://min.io/)
[![.NET 8](https://img.shields.io/badge/.NET-8.0%20LTS-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com/)
[![Angular Jest](https://img.shields.io/badge/Angular-Jest%20jsdom-DD0031?logo=angular&logoColor=white)](https://angular.dev/)

## 📖 About The Project

**Booth Homelab** is a Big Tech SaaS Continuous Testing Rig engineered to run continuous integration, parallel test suites, and infrastructure-as-code automation locally without cloud bill inflation or network bottlenecks.

- **Dual-Runner Testing Fleet:** Dedicated Proxmox VE unprivileged LXC containers running isolated .NET 8 (`pve-runner-01`) and Angular Jest (`pve-runner-angular`) test environments.
- **In-Memory Virtual Bus:** MinIO S3 remote cache across an internal Linux bridge (`vmbr1`) clocking **>800 MiB/s** transfer throughput.
- **Transitive Dependency Graph Testing:** AST-based code-change traversal that builds and tests only affected modules, cutting CI cycle times by up to **80%**.
- **Autonomous & AI-Ready:** Fully documented with human-facing guides ([README.md](README.md), [RUNBOOK.md](RUNBOOK.md)) and machine-readable operational truth ([AI_CONTEXT.md](AI_CONTEXT.md)) for 100% autonomous agent development.

---

## 🏛️ System Architecture & Topology

The homelab leverages an unprivileged Linux Container (LXC) architecture on Proxmox VE connected via an isolated internal bridge (`vmbr1`) operating as an **ultra-high-speed virtual bus** (>800 MiB/s transfer speeds).

```mermaid
graph TD
    subgraph Host ["Proxmox VE 8.4 Hypervisor (AMD-V / Intel Core Ultra)"]
        subgraph VirtualBus ["Virtual Bus Subnet (vmbr1 - 10.99.20.0/24)"]
            CT102["🖥️ CT 102: gha-runner-01\n.NET 8 Unit & Integration Tests\n[Docker-in-LXC | 3 vCPU | 4GB RAM]"]
            CT103["⚡ CT 103: gha-runner-angular\nAngular Standalone Jest Runner\n[Headless jsdom | 2 vCPU | 1.5GB RAM]"]
            CT104["🗄️ CT 104: minio-s3\nDistributed S3 Cache (:9000)\n[7-day TTL | Zstandard Engine]"]
        end
    end

    GitHubActions["☁️ GitHub Actions Orchestrator\n(.github/workflows/sdet-ci.yml)"] -->|"Parallel Dispatch"| CT102
    GitHubActions -->|"Parallel Dispatch"| CT103
    CT102 <-->|"Fetch/Store .NET Cache (>800 MiB/s)"| CT104
    CT103 <-->|"Fetch/Store npm node_modules (>800 MiB/s)"| CT104
```

---

## ⚡ Key Architectural Highlights

### 1. Parallel Dual-Runner Testing Rig
- **.NET 8 Runner (`pve-runner-01` / CT 102):**
  - Dedicated Debian 12 LXC configured with `nesting=1` and `keyctl=1` for Docker-in-LXC.
  - Executes C# unit tests and integration tests (`OrderProcessingIntegrationTests.cs`) deterministically using `/p:Deterministic=true`.
  - Integrates an AST Transitive Dependency Graph analyzer to execute only affected test suites based on `git diff`.
- **Angular Jest Runner (`pve-runner-angular` / CT 103):**
  - Dedicated Debian 12 LXC running Node.js 22 LTS and npm 10.x.
  - Pure headless testing using `jest-preset-angular` and `jsdom` (no Chromium or GUI browser overhead), maintaining an ultra-lean 1.5 GB RAM footprint.
  - Executes 4 spec suites (19 test cases) across components and services in **~2.3 seconds**.

### 2. Virtual Bus Remote Cache (MinIO S3 + Zstandard)
- Dependencies and compilation artifacts are compressed with Zstandard (`zstd -T0`) and stored on **CT 104 MinIO S3** over `10.99.20.20:9000`.
- **Sub-Second Restores:** In warm pipeline runs, `node_modules` (28 MiB) is restored in under 1 second, reducing total job duration from **1m58s** to **18s** (**84% duration reduction**).
- **Immunity from External Outages:** Complete protection against public npm/NuGet rate limits, network jitter, or upstream CDN downtime.

### 3. Network Isolation, Zero-Trust Firewall & Host Protection
- **Layer 2 Bridge Port Isolation & Netfilter:**
  - Bridge port isolation (`isolated on`) prevents East-West frame switching between test runners (`CT 102` and `CT 103`).
  - Kernel netfilter (`HOMELAB-FORWARD`) strictly blocks East-West runner traffic, rejects runner access to the MinIO web console (`:9001`), and permits runner access only to the MinIO S3 API (`:9000`).
  - Host ingress firewall (`HOMELAB-INPUT`) drops runner traffic destined for the host management plane (`:22` SSH and `:8006` Proxmox API).
  - Outbound egress is strictly scoped via `ipset` to authorized package/API registries (`api.github.com`, `registry.npmjs.org`, `api.nuget.org`, Debian mirrors) with default-deny dropping all unauthorized high ports and external IPs.
- **Least-Privilege IAM & Integrity Verification (Cache Poisoning Prevention):**
  - PR runners operate with scoped read-only credentials (`sdet_pr_reader`), while write access (`sdet_ci_writer`) is restricted to the master branch pipeline.
  - S3 archives enforce SHA256 integrity digest verification before decompression into the workspace with path traversal rejection.
- **Zero Public WAN Exposure:**
  - Hypervisor management and containers reside behind Tailscale WireGuard Mesh with Subnet Routing (`10.99.10.0/24`, `10.99.20.0/24`).

### 4. Credential Hardening & Standards

> [!IMPORTANT]
> **Credential Security Advisory:**  
> All administrative and API credentials must be injected via environment variables (`PVE_PASS`, `PVE_TOKEN_SECRET`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`) and encrypted secret stores. Plaintext credentials must never be committed to source control.

#### Production Password Standards (NIST SP 800-63B / CIS Benchmark)
When deploying beyond an isolated development sandbox, generate passwords and secrets compliant with the following standards:
- **Length:** Minimum **16 to 24+ characters** for root/administrative accounts; minimum **32+ characters** for CI/CD API tokens and service keys.
- **Character Composition:** Must contain a balanced mixture of four character classes:
  - Uppercase letters (`A-Z`)
  - Lowercase letters (`a-z`)
  - Decimal digits (`0-9`)
  - Special symbols (`!@#$%^&*()-_+=[{]}|:;,.<>?~`)
- **Entropy & Pattern Defense:** Zero dictionary words, no sequential strings (`123456`, `qwerty`), and no homelab, project, or personal identifiers (`booth`, `minio`, `proxmox`).
- **Role-Based Least Privilege:** Never reuse root administrative credentials (`minioadmin`) across pipeline jobs. Provision dedicated IAM Service Accounts with granular policies (e.g., Read-Only for PR builds, Write for master releases).

---

## 📊 Performance Benchmarks (Live Ground Truth)

| Pipeline Stage | Target Runner | Cold Run (First Boot) | Warm Run (MinIO Cache Hit) | Performance Gain |
| :--- | :--- | :--- | :--- | :--- |
| **Telemetry & Health** | `pve-runner-01` (CT 102) | 9s | 9s | Baseline |
| **.NET Build & Restore** | `pve-runner-01` (CT 102) | 4,630 ms | **16s** (includes toolchain boot) | Incremental |
| **.NET Affected Tests** | `pve-runner-01` (CT 102) | 3,100 ms | **2,175 ms** (6/6 tests pass) | **~30% faster** |
| **Angular Jest Tests** | `pve-runner-angular` (CT 103) | 103,003 ms (npm install) | **4,090 ms** (MinIO hit) | **96% faster** |
| **Total CI Pipeline** | Dual-Runner Parallel | **2m 24s** | **~35s** (All jobs green) | **~75% reduction** |

*Verified in live runs: [`Run #37233575350`](https://github.com/ugritchaichana/booth-homelab/actions/runs/37233575350) and [`Run #37235401356`](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356).*

---

## 📁 Repository Directory Structure

```text
Booth-homelab/
├── .github/
│   ├── actions/                       # Composite actions
│   │   ├── minio-cache/               # MinIO S3 restore and save routines
│   │   ├── run-affected-tests/        # .NET transitive affected test runner
│   │   └── run-angular-jest/          # Angular Jest suite & cache integration
│   └── workflows/
│       ├── pr-labeler.yml             # Auto-labeler for area and application PRs
│       ├── pr-reviewer-guard.yml      # Strips unneeded Copilot reviewers from PRs
│       ├── reusable-sdet-pipeline.yml # Modular 6-stage parallel DAG pipeline
│       ├── sdet-ci.yml                # Top-level orchestrator calling reusable pipeline
│       └── wiki-sync.yml              # Autonomous wiki synchronization engine
│
├── apps/                              # Application Workloads & Test Suites
│   ├── backend/                       # .NET 8 Multi-Project Testing Solution
│   │   ├── SdetTestingRig.sln
│   │   ├── Directory.Build.props      # Enforces /p:Deterministic=true
│   │   ├── src/                       # Domain, Application, Billing.Api, Order.Api
│   │   └── tests/                     # Billing.Api.UnitTests, Order.Api.UnitTests, Order.Api.IntegrationTests
│   └── frontend/                      # Angular 18/19 Standalone Jest Rig
│       ├── package.json               # Dependencies & Jest configuration
│       ├── jest.config.js             # Headless jsdom preset configuration
│       └── src/app/                   # Billing & Order components and spec tests
│
├── iac/                               # Infrastructure as Code
│   ├── tofu/                          # OpenTofu Provisioning (bpg/proxmox)
│   │   ├── flavors.json               # Multi-Cloud Instance Catalog (AWS, GCP, Azure, Hetzner, DO)
│   │   ├── main.tf                    # LXC / VM resources & cloud flavor mapping
│   │   └── modules/                   # Reusable lxc_runner & minio_cache modules
│   ├── ansible/                       # Ansible Configuration & Idempotent Playbooks
│   │   ├── playbooks/site.yml         # Master playbook (host, cache, runners)
│   │   ├── roles/                     # enterprise_firewall, minio_cache, runner_dotnet, runner_angular
│   │   └── inventory/hosts.ini        # Target node and container inventory
│   └── bootstrap/                     # Baremetal Debian-to-PVE host bootstrapping suite (00..06)
│
├── scripts/                           # Developer & CI Helper Scripts
│   ├── apps/                          # Workload test runners (dotnet-affected-test, run-angular-jest)
│   ├── ci/                            # CI utilities (cache-save, cache-restore, sync_wiki)
│   ├── hyperv/                        # Hyper-V Gen2 VM deployment scripts
│   └── proxmox/                       # Proxmox CLI operational & firewall verification scripts
│
├── sandbox/                           # Docker MinIO S3 Local Sandbox (CREEP Hardened)
├── wiki/                              # Markdown documentation auto-synced to GitHub Wiki
├── AGENTS.md                          # Universal machine-readable AI agent operating guide
├── AI_CONTEXT.md                      # Comprehensive ground truth specification for AI agents
├── HANDOFF.md                         # Current system state & operational handoff log
├── RUNBOOK.md                         # Operations, maintenance, and troubleshooting runbooks
└── README.md                          # Project documentation (this file)
```

---

## 🛠️ Quick Start & Common Operations

### 1. Accessing the Proxmox Hypervisor
- **Tailscale Mesh IP:** `https://100.121.209.85:8006/` (or `https://pve:8006/`)
- **Credentials:** Username `root`, password configured in local credentials vault.

### 2. Inspecting Runner Container Status
```bash
# Connect to Proxmox Host via SSH
ssh root@100.121.209.85

# List active containers
pct list

# Check runner systemd services
pct exec 102 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service
pct exec 103 -- systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-angular.service
```

### 3. Inspecting MinIO S3 Remote Cache
```bash
# Connect to runner container and query MinIO client
pct exec 102 -- mc ls minio/build-cache/branches/master/
pct exec 102 -- mc ls minio/build-cache/npm/
```

### 4. Running Local Tests
- **.NET 8 Transitive Affected Tests:**
  ```powershell
  pwsh -File ./scripts/apps/dotnet-affected-test.ps1 -BaseRef origin/master -HeadRef HEAD
  ```
- **Angular Jest Suite:**
  ```bash
  python scripts/ci/run_ct103_tests.py
  ```

### 5. AI-Native Implementation & Agent Onboarding

This repository is optimized for autonomous AI coding assistants (Antigravity, Claude Code, Cursor, Copilot Workspace, Gemini CLI). More than 80% to 100% of implementation can be safely executed by an AI agent:

- **Universal Agent Guide:** [`AGENTS.md`](AGENTS.md) — Authoritative machine-readable operational guide covering commands, empirical traps, and topology.
- **Agent Handover Prompt:** [`HANDOFF.md`](HANDOFF.md) — Turnkey prompt to paste directly into any new AI session to resume immediately.
- **Deep Technical Context:** [`AI_CONTEXT.md`](AI_CONTEXT.md) — Architectural invariants, security policies, and debugging heuristics.
- **Engineering Standards:** [`GEMINI.md`](GEMINI.md) — The 8 Core Engineering Pillars governing clean code, deterministic verification, and zero-trust security.
- **Hardware-Free Local Sandbox:** Launch the complete local S3 cache sandbox with:
  ```powershell
  docker compose -f sandbox/docker-compose.sandbox.yml up -d
  pwsh -File sandbox/verify-sandbox.ps1
  ```

---

## 📚 Documentation & Project Tracking

- **Universal AI Agent Guide:** [AGENTS.md](AGENTS.md) (Standard entrypoint for all AI coding agents)
- **AI Handover Prompt:** [HANDOFF.md](HANDOFF.md) (Turnkey session handover prompt)
- **AI Machine Context:** [AI_CONTEXT.md](file:///c:/Users/Booth/Desktop/MyProjects/Booth-homelab/AI_CONTEXT.md) (Architectural invariants)
- **Online Knowledge Base:** [GitHub Wiki](https://github.com/ugritchaichana/booth-homelab/wiki) (Auto-synced from `wiki/`)
- **Operations Runbook:** [RUNBOOK.md](file:///c:/Users/Booth/Desktop/MyProjects/Booth-homelab/RUNBOOK.md) (Bootstrapping and maintenance procedures)
- **Project Tracking Board:** [GitHub Project #4 (Booth Homelab - SDET & IaC Testing Rig)](https://github.com/users/ugritchaichana/projects/4)

---

## ⚖️ License & Governance

Open-source project maintained under standard dual-identity governance. Built for reproducible, deterministic, and enduring engineering excellence.
