#!/usr/bin/env python3
"""
Automated Provisioning for GitHub Actions Self-Hosted Runner on Proxmox VE 8.4.
CT ID: 102 (gha-runner-01)
Base: Debian 12 Standard LXC
Features: nesting=1, keyctl=1 (Docker-in-LXC enabled)
Network: vmbr1 (10.99.20.101/24 -> Gateway 10.99.20.1)
"""

import sys
import time
import subprocess
import paramiko

PVE_HOST = "100.121.209.85"
PVE_USER = "root"
PVE_PASS = "12345678"
CT_ID = "102"
CT_NAME = "gha-runner-01"
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

def exec_ssh(ssh, cmd, timeout=300):
    print(f"\n[PVE EXEC] {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    code = stdout.channel.recv_exit_status()
    if out:
        print(f"[STDOUT]\n{out}")
    if err and code != 0:
        print(f"[STDERR]\n{err}")
    if code != 0:
        raise RuntimeError(f"Command failed (code {code}): {cmd}")
    return out

def main():
    token = get_runner_registration_token()

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)
    print(f"[+] Connected to Proxmox VE Host ({PVE_HOST})")

    # 1. Check if CT 102 exists
    check_ct = exec_ssh(ssh, f"pct status {CT_ID} 2>/dev/null || true")
    if "status:" in check_ct:
        print(f"[*] CT {CT_ID} already exists. Stopping and destroying for clean recreation...")
        exec_ssh(ssh, f"pct stop {CT_ID} 2>/dev/null || true")
        time.sleep(2)
        exec_ssh(ssh, f"pct destroy {CT_ID} -force 1 -purge 1")

    # 2. Create CT 102
    print(f"\n[*] Creating LXC Container {CT_ID} ({CT_NAME})...")
    create_cmd = (
        f"pct create {CT_ID} {TEMPLATE} "
        f"--hostname {CT_NAME} "
        f"--cores 2 "
        f"--memory 2048 "
        f"--swap 512 "
        f"--rootfs local-lvm:12 "
        f"--ostype debian "
        f"--unprivileged 0 "
        f"--features nesting=1,keyctl=1 "
        f"--net0 name=eth0,bridge=vmbr1,ip=10.99.20.101/24,gw=10.99.20.1 "
        f"--nameserver '1.1.1.1 8.8.8.8' "
        f"--start 1"
    )
    exec_ssh(ssh, create_cmd)
    print(f"[+] CT {CT_ID} created and started.")

    # 3. Wait for CT network ready
    print("[*] Waiting for container network initialization...")
    time.sleep(5)
    exec_ssh(ssh, f"pct exec {CT_ID} -- ping -c 3 1.1.1.1")
    print("[+] Container internet connectivity verified.")

    # 4. Install Prerequisites, Docker, and .NET 8 SDK
    print("[*] Installing Prerequisites (curl, git, jq, docker, dotnet)...")
    setup_script = """#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg lsb-release git jq sudo build-essential \
    docker.io wget libicu-dev

# Install .NET 8 SDK via official Microsoft installer
echo "Installing .NET 8.0 SDK..."
wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
chmod +x /tmp/dotnet-install.sh
/tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

systemctl enable --now docker
docker --version
dotnet --version

# Setup runner user
if ! id "runner" &>/dev/null; then
    useradd -m -s /bin/bash runner
    usermod -aG docker,sudo runner
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# Setup Runner Directory
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# Download latest GitHub Actions Runner
RUNNER_VERSION="2.322.0"
RUNNER_ARCH="x64"
RUNNER_TAR="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"

if [ ! -f "config.sh" ]; then
    echo "Downloading GitHub Actions runner v${RUNNER_VERSION}..."
    curl -o "$RUNNER_TAR" -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}"
    tar xzf "./$RUNNER_TAR"
    rm -f "./$RUNNER_TAR"
    ./bin/installdependencies.sh
fi

chown -R runner:runner /home/runner
"""
    # Write setup script inside CT
    sftp = ssh.open_sftp()
    with sftp.open("/tmp/setup-runner.sh", "w") as f:
        f.write(setup_script)
    sftp.close()

    exec_ssh(ssh, "chmod +x /tmp/setup-runner.sh")
    exec_ssh(ssh, f"pct push {CT_ID} /tmp/setup-runner.sh /root/setup-runner.sh")
    exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash /root/setup-runner.sh", timeout=600)
    print("[+] Base dependencies, Docker, and .NET 8 SDK installed successfully.")

    # 5. Configure and Register Runner
    print(f"[*] Registering Runner with GitHub ({GITHUB_REPO})...")
    config_cmd = (
        f"pct exec {CT_ID} -- su - runner -c '"
        f"cd /home/runner/actions-runner && "
        f"./config.sh --url https://github.com/{GITHUB_REPO} "
        f"--token {token} "
        f"--name pve-runner-01 "
        f"--labels self-hosted,linux,x64,proxmox "
        f"--unattended --replace"
        f"'"
    )
    exec_ssh(ssh, config_cmd)
    print("[+] Runner registered with GitHub Actions!")

    # 6. Install and Start Runner Systemd Service
    print("[*] Installing Runner as a Systemd service...")
    exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash -c 'cd /home/runner/actions-runner && ./svc.sh install runner && ./svc.sh start'")
    print("[+] Runner systemd service started successfully!")

    # 7. Check Runner Status
    status = exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash -c 'cd /home/runner/actions-runner && ./svc.sh status'")
    print(f"[+] Service status:\n{status}")

    ssh.close()
    print("\n" + "=" * 60)
    print("  RUNNER PROVISIONING COMPLETED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    main()
