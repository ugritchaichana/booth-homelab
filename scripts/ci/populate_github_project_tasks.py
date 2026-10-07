#!/usr/bin/env python3
"""
Populates GitHub Issues and synchronizes them to GitHub Project Board:
https://github.com/users/ugritchaichana/projects/4 (linked to booth-homelab)
"""

import sys
import json
import subprocess

PROJECT_NUM = 4
PROJECT_ID = "PVT_kwHOBLpMNs4BlsmX"
OWNER = "ugritchaichana"
REPO = "ugritchaichana/booth-homelab"
FIELD_STATUS_ID = "PVTSSF_lAHOBLpMNs4BlsmXzhkYYrw"
STATUS_DONE_ID = "98236657"
STATUS_TODO_ID = "f75ad846"

TASKS = [
    {
        "title": "[ARCH-01] Hypervisor Groundwork & Nested Virtualization on Proxmox VE 8.4",
        "labels": ["infrastructure", "hypervisor"],
        "status": "Done",
        "body": """### Summary
Configured and verified Proxmox VE 8.4 on AMD Ryzen 5 5600X (Hyper-V Gen 2) with AMD-V nested virtualization passthrough.

### Ground Truth Telemetry
- **Host Hardware:** MSI MS-7C95, Ryzen 5 5600X, 32GB RAM, Windows 11 Pro
- **Hypervisor:** Proxmox VE 8.4.0 (Kernel `Linux 6.8.12-9-pve`)
- **Mesh Connectivity:** Tailscale WireGuard Mesh at `https://100.121.209.85:8006/`
- **Automation Scripts:**
  - `scripts/hyperv/deploy-proxmox-hyperv.ps1`
  - `scripts/proxmox/auto-configure-pve.py`
  - `scripts/proxmox/verify-pve-health.py`

### Verification Status
- REST API Token `root@pam!ai_agent` verified HTTP 200.
- Web GUI accessible via `Linux PAM standard authentication`.
"""
    },
    {
        "title": "[SDET-01] Deterministic Transitive Affected Dependency Graph Test Runner",
        "labels": ["sdet", "testing"],
        "status": "Done",
        "body": """### Summary
Engineered a Git diff-driven transitive dependency graph test runner for .NET 8 solutions based on MSBuild `<ProjectReference>` DAG traversal.

### Key Capabilities
- **Deterministic Compilation:** Enforced via `Directory.Build.props` (`/p:Deterministic=true`).
- **Transitive Impact Analysis:** Editing `Core.Domain` automatically traverses and selects `Order.Api.UnitTests`.
- **Zero-Waste Execution:** Editing non-code skips 100% of test suites.
- **Runners:**
  - `scripts/apps/dotnet-affected-test.ps1` (PowerShell AST)
  - `scripts/apps/dotnet-affected-test.sh` (POSIX Bash for Linux/LXC)
  - Automated 4-scenario TDD verification suite in `tests/verify-affected-graph.ps1` (1.12s execution).
"""
    },
    {
        "title": "[IAC-01] Baremetal Host Bootstrapping Suite for Dedicated Node",
        "labels": ["iac", "automation"],
        "status": "Done",
        "body": """### Summary
Created a modular 7-stage Bash bootstrap suite and portable package for physical hardware migration to baremetal x86_64 host.

### Architecture & Deliverables
- **Hardware Profile:** Multi-Core x86_64 Node (14C/18T Hybrid), 16GB+ LPDDR5X/DDR5, Wi-Fi / Ethernet.
- **Routed NAT Topology:** Dual bridges `vmbr0` and `vmbr1` with IP forwarding & Wi-Fi masquerade rules.
- **Power & Stability:** `HandleLidSwitch=ignore` and persistent Wi-Fi powersave killswitch service.
- **Bundle Archive:** `pve-bootstrap-bundle.tar.gz` ready for one-command execution via `./bootstrap.sh`.
- **Runbook:** Comprehensive 5-phase operational runbook authored in `RUNBOOK.md`.
"""
    },
    {
        "title": "[CI-01] Proxmox Self-Hosted GitHub Actions Runner (CT 102 Debian LXC)",
        "labels": ["ci-cd", "proxmox"],
        "status": "Done",
        "body": """### Summary
Provisioned a dedicated, isolated Self-Hosted GitHub Actions runner in a Debian 12 LXC container inside Proxmox.

### Container Specification
- **Container ID:** CT 102 (`gha-runner-01`)
- **OS:** Debian 12 Bookworm Standard LXC
- **Features:** `nesting=1,keyctl=1` (Enables Docker-in-LXC)
- **Runtimes:** Docker Engine `20.10.24`, .NET 8.0 SDK `8.0.425`, Git `2.39.5`
- **Runner Agent:** Actions Runner `v2.337.0` running as a systemd service daemon.
- **Labels:** `self-hosted`, `Linux`, `X64`, `proxmox`
- **Automation:** `scripts/proxmox/provision-runner.py`
"""
    },
    {
        "title": "[CACHE-01] Enterprise Distributed Remote Cache on Proxmox (CT 104 MinIO S3)",
        "labels": ["caching", "security"],
        "status": "Done",
        "body": """### Summary
Deployed an enterprise S3-compatible remote cache server on Proxmox in Alpine Linux, connected over internal bridge `vmbr1` (Virtual Bus).

### Specifications & Performance
- **Container ID:** CT 104 (`object-store`) on Alpine Linux 3.23 (RAM footprint < 50MB)
- **Network Interface:** `internal object store endpoint` (Direct virtual bus transfer at 836+ MiB/s)
- **Buckets:**
  - `build-cache`: Stores Zstandard compressed compilation artifacts and NuGet packages.
  - `test-artifacts`: Stores `.trx` test reports.
- **Lifecycle & Security:**
  - 7-day ILM expiration policy to prevent storage exhaustion on homelab.
  - CREEP Hardened (CVE-2025-36852) with branch-scoped cache isolation (`build-cache/branches/<branch>/`).
"""
    },
    {
        "title": "[PERF-01] Deep Optimization Tuning Benchmark (2 PRs Verification)",
        "labels": ["performance", "benchmarks"],
        "status": "Done",
        "body": """### Summary
Conducted live performance benchmark tests across Master baseline, PR #1, and PR #2 to measure build and test acceleration.

### Benchmark Telemetry Results
- **Cold Run (Master):** Build duration 4,630 ms | Generated 72MB Zstd cache to MinIO S3 in 1.4s.
- **PR #1 (Billing.Api modified):**
  - Downloaded 71.68 MiB from MinIO at **836.59 MiB/s** in **110 ms**.
  - Decompressed in **987 ms**.
  - Executed ONLY `Billing.Api.UnitTests` (Skipped `Order.Api.UnitTests` 100%).
  - Total pipeline time: **23s**.
- **PR #2 (Order.Api modified):**
  - Cache Hit! Downloaded in **128 ms**.
  - Recompiled in **3,616 ms** with MSBuild Timestamp Synchronization.
  - Executed ONLY `Order.Api.UnitTests` (Skipped `Billing.Api.UnitTests` 100%).
  - Saved new cache in **1,615 ms** | Total pipeline time: **24s**.
"""
    },
    {
        "title": "[SEC-01] Enterprise Zero-Trust Netfilter Firewall & Layer 2 Bridge Port Isolation",
        "labels": ["security", "networking"],
        "status": "Done",
        "body": """### Summary
Implemented enterprise-grade zero-trust network segmentation and bridge port isolation on Proxmox VE 8.4.

### Capabilities & Assertions
- **L2 Port Isolation:** Enforced `isolated on` on `veth102i0` and `veth103i0`.
- **L3/L4 Netfilter Chain:** Persistent `HOMELAB-FORWARD` chain in `/etc/network/if-up.d/homelab-firewall`.
- **East-West Traffic:** 100% packet loss between CT 102 (.NET) and CT 103 (Angular).
- **Service Isolation:** Runner access to MinIO S3 API (:9000) allowed; Web Console (:9001) blocked.
- **Egress Whitelist:** Outbound restricted strictly to ports 53, 80, 443, 123 (Default DROP).
- **Verification:** 10/10 automated assertions passed with a script that was retired together with this firewall (ADR 0020).

### Status Note
Retired with the previous host (ADR 0020). The current firewall is owned by Ansible (ADR 0025, ADR 0027) and guest isolation is proven per ADR 0031.
"""
    },
    {
        "title": "[IAC-02] Declarative OpenTofu Provisioning Engine with Multi-Cloud Flavor Catalog",
        "labels": ["iac", "opentofu"],
        "status": "Done",
        "body": """### Summary
Engineered declarative Infrastructure as Code using OpenTofu 1.13 and provider `bpg/proxmox` (~> 0.68.0).

### Key Features
- **Multi-Cloud Flavor Catalog (`iac/tofu/flavors.json`, ADR 0017):** Abstracts hardware sizing using AWS (t3/c5/m5), GCP (e2/c2), Azure (B/D/F), Hetzner (cx/cpx), and DigitalOcean profiles.
- **Dynamic HCL Mapping:** Resolved vCPU, RAM, and Disk allocations from the selected cloud provider and instance flavor; the root module that did this was replaced by the stacks under `iac/tofu/stacks/` and nothing reads the catalog yet.
- **Modular Topology:** The runner and cache modules are gone. The current module is `iac/tofu/modules/proxmox/sdn` (guest network, ADR 0030), called by the stacks `iac/tofu/stacks/proxmox-host` and `iac/tofu/stacks/r15-probe`.
- **Inventory:** The generated Ansible inventory was replaced by one hand-kept file, `iac/inventory/hosts.yml`, read by Ansible and OpenTofu (ADR 0021).
"""
    },
    {
        "title": "[IAC-03] Enterprise Ansible Configuration Management & Idempotent Playbook Fleet",
        "labels": ["iac", "ansible"],
        "status": "Done",
        "body": """### Summary
Engineered declarative, idempotent configuration management in `iac/ansible/` for the Proxmox hosts.

### Deliverables
- **Orchestrators:** `playbooks/bootstrap.yml` (first contact as root) and `playbooks/site.yml` (steady state); `playbooks/r15-verify.yml` runs the isolation proof on demand.
- **Structured Roles:** `base`, `hyperv_guest`, `pve_host`, `pve_api_identity`, `pve_firewall`. The Ansible content of the previous host was retired (ADR 0020, ADR 0023).
- **Variables:** Host data lives in `iac/inventory/` (`hosts.yml`, `group_vars/`, `host_vars/`); secrets are SOPS files under `iac/secrets/` (ADR 0009).
"""
    },
    {
        "title": "[REFACTOR-01] Modern Workload Directory Restructuring (apps/) & IaC Decoupling",
        "labels": ["refactoring", "architecture"],
        "status": "Done",
        "body": """### Summary
Restructured repository directory hierarchy for universal 5-second clarity, removing domain jargon (`sdet/` -> `apps/`) and elevating `iac/` as a first-class citizen.

### Directory Layout
- `apps/backend/`: .NET 8 solution with deterministic MSBuild and DAG diff runner.
- `apps/frontend/`: Angular 18/19 standalone Jest test suite with pure headless jsdom.
- `iac/`: Clean separation into `tofu/`, `ansible/`, `inventory/`, `secrets/`, and `proxmox/`; the old `bootstrap/` tree was retired (ADR 0020).
- `scripts/`: Compact developer CLI tools only (`scripts/apps/`, `scripts/ci/`, `scripts/proxmox/`).
"""
    },
    {
        "title": "[ROADMAP-02] Shared Package Mirror Cache (CT 101 BaGet & Verdaccio)",
        "labels": ["caching", "optimization"],
        "status": "Todo",
        "body": """### Summary
Deploy CT 101 (`shared-cache`) to host package registry proxies and Docker mirrors.

### Target Services
- **BaGet (:5000):** Self-hosted read-through NuGet package cache.
- **Verdaccio (:4873):** Lightweight npm private proxy/registry.
- **Docker Registry Mirror (:5001):** Pull-through cache for Docker Hub images.
"""
    }
]

import tempfile
import os

def run(cmd):
    res = subprocess.run(cmd, shell=True, capture_output=True, encoding="utf-8", errors="replace")
    if res.returncode != 0 and "already exists" not in res.stderr:
        print(f"[ERR] {cmd}\n{res.stderr.strip()}")
    return res.stdout.strip()

def main():
    print("=" * 60)
    print(f" Syncing Homelab Tasks to GitHub Projects #{PROJECT_NUM}")
    print("=" * 60)

    for task in TASKS:
        title = task["title"]
        body = task["body"]
        labels = ",".join(task["labels"])
        status = task["status"]

        print(f"\n[*] Processing Task: {title}")
        
        # 1. Create or Find Issue
        check_issue = run(f'gh issue list --repo {REPO} --state all --search "{title[:30]}" --json number,url,title')
        issue_data = json.loads(check_issue) if check_issue else []
        matched = [i for i in issue_data if i.get("title") == title]
        
        if matched:
            issue_url = matched[0]["url"]
            print(f"    [INFO] Issue already exists: {issue_url}")
        else:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tf:
                tf.write(body)
                tf_path = tf.name

            # Ensure labels exist or ignore label error
            label_flags = " ".join([f'--label "{l}"' for l in task["labels"]])
            create_cmd = f'gh issue create --repo {REPO} --title "{title}" --body-file "{tf_path}"'
            issue_url = run(create_cmd)
            try:
                os.remove(tf_path)
            except OSError:
                pass
            print(f"    [PASS] Created Issue: {issue_url}")
            if status == "Done" and issue_url:
                run(f'gh issue close {issue_url} --reason "completed"')

        # 2. Add Issue to Project
        add_cmd = f'gh project item-add {PROJECT_NUM} --owner {OWNER} --url {issue_url} --format json'
        item_raw = run(add_cmd)
        if item_raw:
            try:
                item_id = json.loads(item_raw).get("id")
                target_status_id = STATUS_DONE_ID if status == "Done" else STATUS_TODO_ID
                edit_cmd = f'gh project item-edit --id {item_id} --project-id {PROJECT_ID} --field-id {FIELD_STATUS_ID} --single-select-option-id {target_status_id}'
                run(edit_cmd)
                print(f"    [PASS] Added to Project #{PROJECT_NUM} with Status: {status}")
            except Exception as e:
                print(f"    [WARN] Failed to parse item JSON: {e}")

    print("\n" + "=" * 60)
    print(" ALL TASKS SUCCESSFULLY RECORDED ON GITHUB PROJECTS!")
    print("=" * 60)

if __name__ == "__main__":
    main()
