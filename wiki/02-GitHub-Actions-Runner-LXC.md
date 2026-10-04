# 02. GitHub Actions Runner (CT 102 Debian LXC)

## 1. Container Provisioning & Configuration

The primary execution runner is housed in container **CT 102 (`gha-runner-01`)**, running **Debian 12 Bookworm Standard**.

### Proxmox Container Configuration (`/etc/pve/lxc/102.conf`)
```ini
arch: amd64
cores: 3
hostname: gha-runner-01
memory: 4096
swap: 1024
ostype: debian
rootfs: local:102/vm-102-disk-0.raw,size=20G
net0: name=eth0,bridge=vmbr1,ip=10.99.20.101/24,gw=10.99.20.1
features: nesting=1,keyctl=1
unprivileged: 1
```

### Critical Container Features:
- **`nesting=1`**: Allows systemd containers to mount cgroups and run inner container runtimes (Docker-in-LXC).
- **`keyctl=1`**: Enables Linux kernel keyring syscalls within unprivileged containers, required for Docker authentication and secure token handling.

---

## 2. Runtime Environment & Toolchain

The runner image is provisioned with exact SDET development toolchains:
- **GitHub Actions Runner:** `v2.337.0` (Latest release supporting Node.js 20/24 actions)
- **.NET SDK:** `8.0.425` (LTS runtime and build tools)
- **Docker Engine:** `20.10.24` / Containerd
- **Compression Tools:** `zstd` (Zstandard compression engine for high-speed cache payloads)
- **MinIO Client:** `mc` (`vRELEASE.2025-02-21T01-50-48Z`)

---

## 3. GitHub Actions Runner Daemon Setup

The runner runs as a persistent systemd background service under the dedicated user `runner`:

```bash
# Service status check
systemctl status actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service

# Restart runner service
systemctl restart actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service

# View live runner logs
journalctl -u actions.runner.ugritchaichana-booth-homelab.gha-runner-01.service -f
```

### Runner Metadata & Labels
```json
{
  "name": "pve-runner-01",
  "os": "Linux",
  "status": "online",
  "version": "2.337.0",
  "labels": [
    "self-hosted",
    "Linux",
    "X64",
    "proxmox"
  ]
}
```

---

## 4. GitHub Actions Workflow Targeting

In `.github/workflows/sdet-pipeline.yml`, jobs target this runner using the `proxmox` label:

```yaml
jobs:
  sdet-verification:
    name: Verify on Proxmox Self-Hosted Runner
    runs-on: [self-hosted, linux, proxmox]
```

This guarantees that workflows execute locally inside Proxmox without consuming GitHub cloud runner minutes or leaving the local subnet.
