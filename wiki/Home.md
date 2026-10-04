# Booth Homelab & SDET Infrastructure Knowledge Base

Welcome to the central knowledge repository for **Booth Homelab** — an enterprise-grade CI/CD and SDET testing rig running on Proxmox VE 8.4 (nested inside Hyper-V on Windows 11 host).

---

## 🧭 Navigation & Table of Contents

| Section | Description | Document Link |
| :--- | :--- | :--- |
| **01. Architecture & Design** | Hypervisor topology, DMZ network bridges, LXC container specifications | [[01-Architecture-and-Design]] |
| **02. GitHub Actions Runner** | CT 102 Debian 12 LXC provisioning, Docker-in-LXC, systemd runner daemon | [[02-GitHub-Actions-Runner-LXC]] |
| **03. MinIO S3 Remote Cache** | CT 104 Alpine Linux MinIO cache, Zstandard compression, virtual bus throughput | [[03-Enterprise-MinIO-S3-Cache]] |
| **04. Transitive Affected Testing** | Monorepo dependency graph, git diff detection, MSBuild timestamp sync | [[04-SDET-Transitive-Affected-Testing]] |
| **05. Benchmark Results** | Live telemetry data: Cold run vs. PR #1 vs. PR #2 | [[05-Performance-Benchmark-Results]] |
| **06. Operational Runbooks** | Disaster recovery, networking rescue, host bootstrap, and troubleshooting | [[06-Operational-Runbooks-and-Troubleshooting]] |

---

## ⚡ System Highlights & Performance SLA

```mermaid
graph TD
    subgraph Host ["Acer Swift Go 14 / Windows 11 Host"]
        HV["Hyper-V Virtual Switch (Default Switch NAT)"]
        PVE["Proxmox VE 8.4 (4 vCPU, 10GB RAM)"]
    end

    subgraph Proxmox ["Proxmox Internal Network (vmbr1: 10.99.20.0/24)"]
        CT100["CT 100: Net Gateway (nftables / Zero-Trust)"]
        CT101["CT 101: Shared Cache (BaGet & Verdaccio)"]
        CT102["CT 102: GHA Runner .NET (Debian 12 + Docker)"]
        CT103["CT 103: GHA Runner Angular (Debian 12 + Jest jsdom)"]
        CT104["CT 104: MinIO S3 (Alpine Linux 3.23)"]
    end

    HV -->|vmbr0 WAN| PVE
    PVE -->|vmbr1 DMZ| CT102
    PVE -->|vmbr1 DMZ| CT103
    PVE -->|vmbr1 DMZ| CT104
    CT102 <-->|Virtual Bus @ 800+ MiB/s| CT104
    CT103 <-->|Virtual Bus @ 800+ MiB/s| CT104
```

### Key Performance Metrics
- **Virtual Bus Cache Throughput:** **>800 MiB/s** across `vmbr1` internal bridge.
- **Remote Cache Download Time:** **<1s** for both .NET and npm Zstd payloads.
- **Angular Jest Execution:** **4.09s** (19 specs across 4 suites) with 84% job duration reduction.
- **Affected Test Reduction:** 100% skip rate on unaffected test suites.
- **Dual-Runner Parallel Execution:** Both .NET and Angular suites execute concurrently.

---

## 🔗 External Traceability Links
- **GitHub Repository:** [ugritchaichana/booth-homelab](https://github.com/ugritchaichana/booth-homelab)
- **GitHub Project Board:** [Booth Homelab SDET Delivery (#4)](https://github.com/users/ugritchaichana/projects/4)
- **MinIO Web Console:** `http://100.121.209.85:9001` (Direct SSH Port Forward)
- **Proxmox Web GUI:** `https://100.121.209.85:8006` (Linux PAM authentication)
