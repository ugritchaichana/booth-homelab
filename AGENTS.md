# AGENTS.md: Universal AI Agent Operating Guide

This document is the authoritative, machine-readable operational guide for AI coding assistants (Antigravity, Claude Code, Cursor, Copilot, Windsurf, etc.) operating on the `Booth-homelab` repository.

---

## 1. Project Mission & Architecture

**Booth-homelab** is a Continuous Testing (SDET) and Infrastructure-as-Code (IaC) rig engineered to execute parallel automated test suites locally with sub-second remote caching and zero-trust network isolation.

### Core Stack
- **Hypervisor:** Proxmox VE 8.4.0 (Kernel `Linux 6.8.12-9-pve`, Debian 12 Bookworm)
- **CI Runners (LXC):**
  - **CT 102 (`gha-runner-01` / `10.99.20.101`):** .NET 8 LTS, Docker-in-LXC (`nesting=1,keyctl=1`), AST dependency graph diff runner.
  - **CT 103 (`gha-runner-angular` / `10.99.20.103`):** Node.js 20 LTS, Angular Jest with pure headless `jsdom` (strict 1.5 GB RAM ceiling).
- **Remote Cache (LXC):**
  - **CT 104 (`minio-s3` / `10.99.20.20`):** Alpine Linux 3.23 MinIO S3 API (`:9000`), Web Console (`:9001`), Zstandard compression, in-memory bridge throughput >800 MiB/s.
- **Network Isolation:**
  - Layer 2 bridge port isolation on `vmbr1` (`isolated on` for `veth102i0` and `veth103i0`).
  - Layer 3/4 `HOMELAB-FORWARD` netfilter chain: East-West runner traffic dropped, runner access to `:9001` dropped, runner internet egress restricted to ports 53, 80, 443, 123.
- **S3 Bucket Policy:**
  - `build-cache` and `test-artifacts`: private (no anonymous access). Runners read through a bucket-scoped IAM reader (`iac/minio/policies/build-cache-reader.json`); the writer credential is held only by the master cache-save job via the `cache-writer` GitHub Environment.

---

## 2. Deterministic Verification Commands (AI Execution Gate)

Every AI agent MUST verify changes using these automated commands. Do not conclude tasks without concrete exit code 0 output:

```bash
# 1. Run .NET 8 Backend Unit & Integration Tests (6 tests / 3 suites):
dotnet test apps/backend/SdetTestingRig.sln --verbosity quiet

# 2. Run Angular Jest Standalone Tests (19 tests / 4 suites):
# On Proxmox Runner CT 103:
python scripts/ci/run_ct103_tests.py
# Or inside apps/frontend (if node_modules installed):
npm test --prefix apps/frontend -- --silent

# 3. Verify .NET AST Transitive Dependency Graph Diff Runner (5 scenarios):
pwsh -File ./tests/verify-affected-graph.ps1

# 4. Verify Enterprise Zero-Trust Firewall (13/13 assertions):
python scripts/proxmox/verify-enterprise-firewall.py

# 5. Verify Language Compliance (Must return 0 Thai characters across repo):
python -c "import os, re; p=re.compile(r'[\u0E00-\u0E7F]'); found=[os.path.join(r,f) for r,_,fs in os.walk('.') if '.git' not in r for f in fs if f.endswith(('.md','.py','.sh','.ps1','.cs','.ts')) and p.search(open(os.path.join(r,f),encoding='utf-8',errors='ignore').read())]; print('PASS: 0 Thai chars' if not found else f'FAIL: {found}')"
```

---

## 3. Local Sandbox Fallback (No Proxmox Required)

If operating on a development machine without direct access to the Proxmox hypervisor, spin up the local Docker MinIO S3 sandbox:

```powershell
# Start local S3 cache sandbox with CREEP-hardened policies
docker compose -f sandbox/docker-compose.sandbox.yml up -d

# Verify sandbox policies and read/write separation
pwsh -File sandbox/verify-sandbox.ps1

# Teardown sandbox cleanly
pwsh -File sandbox/teardown.ps1
```

---

## 4. The 8 Core Engineering Pillars (Operating Standards)

1. **Clean Code Style:** Single responsibility, intention-revealing names, zero dead code.
2. **Idiomatic Best Practices:** Idiomatic .NET 8 C#, Angular Standalone TypeScript, modern Python, and POSIX shell.
3. **Compact, High-Signal Comments:** Explain "Why" and non-obvious invariants; never restate obvious code.
4. **100% Universal English:** All repository code, comments, commits, PRs, docs, and wiki MUST be in English.
5. **Deterministic Verification:** Every implementation or bugfix must be proven with automated CLI execution.
6. **Zero-Trust Security & Secrets Hygiene:** Fail-closed networks, least privilege, zero plaintext secrets in git.
7. **Observability & Telemetry:** Emit structured output and exit codes enabling 60-second root cause diagnosis.
8. **Hardware Headroom Awareness:** Respect memory limits (Angular jsdom 1.5 GB limit) and ensure one-command disaster recovery.

---

## 5. Known Empirical Traps & Hard-Learned Solutions

| Trap | Failure Symptom | Surgical Solution |
| :--- | :--- | :--- |
| **OpenSSH Interactive Prompt** | `ssh root@100.121.209.85` in PowerShell hangs indefinitely | Always use Python `paramiko` with explicit password for non-interactive execution |
| **Actions Checkout Order** | Composite actions fail with file not found | `actions/checkout@v4` must always be the very first step in every GitHub Actions job |
| **LXC File Injection** | Files placed in `/tmp` on Proxmox host are invisible inside containers | Use `pct push <vmid> <host_path> <container_path>` |
| **Debian 12 UsrMerge** | `mc` binary path resolution errors | Resolve dynamically: `$(command -v mc || echo '/usr/bin/mc')` |
| **Angular Memory Spike** | Container OOM kills Jest process | Never install Chrome/Playwright in CT 103; use headless `jsdom` + `jest-preset-angular` |
| **Git Identity Mismatch** | Commits rejected by identity guard | Enforce `ugritchaichana` (`ugritchaichana@users.noreply.github.com`); never use corporate identity |

---

## 6. Proxmox Remote Control Pattern (Python Paramiko)

When an agent needs to inspect or configure the live Proxmox host, use this standard snippet:

```python
import paramiko

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("100.121.209.85", username="root", password="[VAULT_PASSWORD]")
stdin, stdout, stderr = ssh.exec_command("pct list")
print(stdout.read().decode("utf-8", errors="ignore"))
ssh.close()
```

---

## 7. Wiki Synchronization SOP

The project documentation is mirrored live to the GitHub Wiki. Whenever editing files in `wiki/`, run:

```bash
python scripts/ci/sync_wiki.py
```
