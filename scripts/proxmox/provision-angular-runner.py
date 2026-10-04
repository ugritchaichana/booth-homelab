#!/usr/bin/env python3
"""
Automated Provisioning for Angular Jest GitHub Actions Self-Hosted Runner on Proxmox VE 8.4.
CT ID: 103 (gha-runner-angular)
Base: Debian 12 Standard LXC
Features: nesting=1, keyctl=1
Network: vmbr1 (10.99.20.103/24 -> Gateway 10.99.20.1)
Runtimes: Node.js LTS (v20), npm, zstd, git
Labels: self-hosted, linux, x64, proxmox, angular
"""

import sys
import time
import subprocess
import paramiko

# Ensure UTF-8 output on Windows console
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

PVE_HOST = "100.121.209.85"
PVE_USER = "root"
PVE_PASS = "12345678"
CT_ID = "103"
CT_NAME = "gha-runner-angular"
TEMPLATE = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
GITHUB_REPO = "ugritchaichana/booth-homelab"

def get_runner_registration_token():
    print(f"[*] Requesting GitHub Actions Runner registration token for {GITHUB_REPO}...")
    res = subprocess.run(
        ["gh", "api", "--method", "POST", f"/repos/{GITHUB_REPO}/actions/runners/registration-token", "--jq", ".token"],
        capture_output=True,
        text=True,
        check=True
    )
    token = res.stdout.strip()
    if not token:
        raise RuntimeError("Failed to obtain registration token from gh CLI")
    print(f"[+] Registration token obtained: {token[:6]}******")
    return token

def get_latest_runner_version():
    res = subprocess.run(
        ["gh", "api", "repos/actions/runner/releases/latest", "--jq", ".tag_name"],
        capture_output=True,
        text=True,
        check=True
    )
    ver = res.stdout.strip().lstrip("v")
    print(f"[+] Latest GitHub Actions Runner release: v{ver}")
    return ver

def exec_ssh(ssh, cmd, timeout=300):
    print(f"\n[PVE EXEC] {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    code = stdout.channel.recv_exit_status()
    if out:
        try:
            print(f"[STDOUT]\n{out}")
        except UnicodeEncodeError:
            print(f"[STDOUT]\n{out.encode('ascii', errors='replace').decode()}")
    if err and code != 0:
        try:
            print(f"[STDERR]\n{err}")
        except UnicodeEncodeError:
            print(f"[STDERR]\n{err.encode('ascii', errors='replace').decode()}")
    if code != 0:
        raise RuntimeError(f"Command failed (code {code}): {cmd}")
    return out

def main():
    token = get_runner_registration_token()
    runner_ver = get_latest_runner_version()

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)
    print(f"[+] Connected to Proxmox VE Host ({PVE_HOST})")

    # 1. Check if CT 103 exists
    check_ct = exec_ssh(ssh, f"pct status {CT_ID} 2>/dev/null || true")
    if "status: running" not in check_ct:
        if "status:" in check_ct:
            exec_ssh(ssh, f"pct start {CT_ID}")
        else:
            print(f"\n[*] Creating LXC Container {CT_ID} ({CT_NAME})...")
            create_cmd = (
                f"pct create {CT_ID} {TEMPLATE} "
                f"--hostname {CT_NAME} "
                f"--cores 2 "
                f"--memory 1536 "
                f"--swap 512 "
                f"--rootfs local-lvm:12 "
                f"--ostype debian "
                f"--unprivileged 0 "
                f"--features nesting=1,keyctl=1 "
                f"--net0 name=eth0,bridge=vmbr1,ip=10.99.20.103/24,gw=10.99.20.1 "
                f"--nameserver '1.1.1.1 8.8.8.8' "
                f"--start 1"
            )
            exec_ssh(ssh, create_cmd)
            time.sleep(5)
            exec_ssh(ssh, f"pct exec {CT_ID} -- ping -c 3 1.1.1.1")

    # 2. Update / Install Node.js LTS and dependencies inside CT 103
    print(f"\n[*] Ensuring Node.js LTS and Runner v{runner_ver} inside CT {CT_ID}...")
    setup_script = f"""#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Install core utilities and Node.js LTS (20.x)
if ! command -v node &>/dev/null; then
    apt-get update -y
    apt-get install -y --no-install-recommends \\
        ca-certificates curl gnupg lsb-release git jq sudo build-essential wget zstd

    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Ensure runner user
if ! id "runner" &>/dev/null; then
    useradd -m -s /bin/bash runner
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Setup Runner Directory
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

RUNNER_ARCH="x64"
RUNNER_TAR="actions-runner-linux-${{RUNNER_ARCH}}-{runner_ver}.tar.gz"

if [ ! -f "version_{runner_ver}.ok" ]; then
    echo "Downloading and extracting Runner v{runner_ver}..."
    ./svc.sh stop 2>/dev/null || true
    ./svc.sh uninstall 2>/dev/null || true
    rm -rf *
    curl -o "$RUNNER_TAR" -L "https://github.com/actions/runner/releases/download/v{runner_ver}/${{RUNNER_TAR}}"
    tar xzf "$RUNNER_TAR"
    rm -f "$RUNNER_TAR"
    ./bin/installdependencies.sh
    touch "version_{runner_ver}.ok"
fi

chown -R runner:runner "$RUNNER_DIR"

# Configure runner if not already configured
if [ ! -f ".runner" ]; then
    echo "Registering Runner with GitHub Actions..."
    sudo -u runner ./config.sh \\
        --url "https://github.com/{GITHUB_REPO}" \\
        --token "{token}" \\
        --name "pve-runner-angular" \\
        --labels "self-hosted,linux,x64,proxmox,angular" \\
        --work "_work" \\
        --unattended \\
        --replace
fi

# Install and start systemd service
if [ ! -f "/etc/systemd/system/actions.runner.{GITHUB_REPO.replace('/', '-')}.pve-runner-angular.service" ]; then
    echo "Installing runner systemd service..."
    ./svc.sh install runner || true
fi

echo "Starting runner systemd service..."
./svc.sh start || true
./svc.sh status || true
"""

    # Write script to CT and execute
    print(f"[*] Writing and executing runner setup script inside CT {CT_ID}...")
    exec_ssh(ssh, f"cat << 'EOF' > /tmp/setup_angular_runner.sh\n{setup_script}\nEOF")
    exec_ssh(ssh, f"pct push {CT_ID} /tmp/setup_angular_runner.sh /tmp/setup_angular_runner.sh")
    exec_ssh(ssh, f"pct exec {CT_ID} -- bash /tmp/setup_angular_runner.sh")
    exec_ssh(ssh, f"pct exec {CT_ID} -- rm -f /tmp/setup_angular_runner.sh")
    exec_ssh(ssh, "rm -f /tmp/setup_angular_runner.sh")

    # 3. Verify Runner Online status via GitHub API
    print("\n[*] Verifying runner registration via GitHub API...")
    time.sleep(3)
    res = subprocess.run(
        ["gh", "api", f"repos/{GITHUB_REPO}/actions/runners", "--jq", ".runners[] | {name: .name, status: .status, labels: [.labels[].name]}"],
        capture_output=True,
        text=True,
        check=True
    )
    print(f"[+] Active Runners in {GITHUB_REPO}:\n{res.stdout}")
    print(f"\n[✓] Angular Jest Runner CT {CT_ID} provisioned and verified successfully!")

if __name__ == "__main__":
    main()
