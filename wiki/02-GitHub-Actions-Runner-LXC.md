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
unprivileged: 0
```

The runner CTs are provisioned privileged: [`provision-runner.py#L151`](https://github.com/ugritchaichana/booth-homelab/blob/179f82606f06823ebb04773777d3d1fd8c2728ae/scripts/proxmox/provision-runner.py#L151) and [`provision-angular-runner.py#L186`](https://github.com/ugritchaichana/booth-homelab/blob/179f82606f06823ebb04773777d3d1fd8c2728ae/scripts/proxmox/provision-angular-runner.py#L186) both pass `--unprivileged 0`. Only the OpenTofu module declares `unprivileged = true` ([`main.tf#L10`](https://github.com/ugritchaichana/booth-homelab/blob/179f82606f06823ebb04773777d3d1fd8c2728ae/iac/tofu/modules/lxc_runner/main.tf#L10)). Moving the live runners to unprivileged CTs is open.

### Critical Container Features:
- **`nesting=1`**: Allows systemd containers to mount cgroups and run inner container runtimes (Docker-in-LXC).
- **`keyctl=1`**: Enables Linux kernel keyring syscalls within the runner containers, required for Docker authentication and secure token handling.

---

## 2. Runtime Environment & Toolchain

The runner image is provisioned with exact SDET development toolchains:
- **GitHub Actions Runner:** `v2.337.0` ([job log](https://github.com/ugritchaichana/booth-homelab/actions/runs/37235401356/job/111533373752) prints `Current runner version: '2.337.0'`)
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
    "proxmox",
    "dotnet"
  ]
}
```

---

## 4. Angular Jest Runner (CT 103 Debian LXC)

For frontend SDET unit testing, **CT 103 (`gha-runner-angular`)** is deployed as an isolated, dedicated runner:

- **Hostname:** `gha-runner-angular` (`10.99.20.103/24` -> GW `10.99.20.1`)
- **OS:** Debian 12 Bookworm LXC (`cores: 2`, `memory: 1536`, `swap: 512`)
- **Runtimes:** Node.js v22 LTS, npm 10.x, MinIO Client (`mc`), zstd
- **Labels:** `[self-hosted, Linux, X64, proxmox, angular]`

---

## 5. GitHub Actions Workflow Targeting Matrix

Jobs target their respective isolated environments using specialized runner labels:

```yaml
# .NET 8 Backend Build & Tests -> Executed on CT 102
runs-on: [self-hosted, linux, proxmox, dotnet]

# Angular Jest Unit Tests -> Executed in parallel on CT 103
runs-on: [self-hosted, linux, proxmox, angular]
```

This dual-runner setup allows backend integration tests and frontend Jest unit tests to execute **concurrently** on dedicated Proxmox containers.
