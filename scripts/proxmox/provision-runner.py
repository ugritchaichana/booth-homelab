#!/usr/bin/env python3
"""
Automated Provisioning for GitHub Actions Self-Hosted Runner on Proxmox VE 8.4.
CT ID: 102 (gha-runner-01)
Base: Debian 12 Standard LXC
Features: nesting=1, keyctl=1 (Docker-in-LXC enabled)
Network: vmbr1 (10.99.20.101/24 -> Gateway 10.99.20.1)
"""

import os
import sys
import time
import subprocess
import paramiko

# Ensure UTF-8 output on Windows console
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

PVE_HOST = os.environ.get("PVE_HOST", "100.121.209.85")
PVE_USER = os.environ.get("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]
CT_ID = "102"
CT_NAME = "gha-runner-01"
TEMPLATE = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
GITHUB_REPO = "ugritchaichana/booth-homelab"
RUNNER_LABELS = "self-hosted,linux,x64,proxmox,dotnet"

RUNNER_MODE = os.environ.get("RUNNER_MODE", "persistent").strip().lower() or "persistent"
if RUNNER_MODE not in ("persistent", "ephemeral"):
    raise SystemExit(f"RUNNER_MODE must be 'persistent' or 'ephemeral', got '{RUNNER_MODE}'")
EPHEMERAL = RUNNER_MODE == "ephemeral"
SUPERVISOR_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ephemeral")
SUPERVISOR_ENV = "/etc/homelab/runner-supervisor.env"
SUPERVISOR_UNIT = f"homelab-ephemeral-runner@{CT_ID}.service"

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

def seal_and_install_supervisor(ssh):
    print(f"\n[*] Ephemeral mode: snapshotting CT {CT_ID} as 'clean' and installing the host supervisor...")
    exec_ssh(ssh, f"if pct status {CT_ID} | grep -q running; then pct shutdown {CT_ID} --forceStop 1 --timeout 60; fi")
    exec_ssh(ssh, f"if pct listsnapshot {CT_ID} | grep -qE '(^|[[:space:]])clean([[:space:]]|$)'; then pct delsnapshot {CT_ID} clean; fi")
    exec_ssh(ssh, f"pct snapshot {CT_ID} clean")

    exec_ssh(ssh, "command -v jq >/dev/null || apt-get install -y jq")
    exec_ssh(ssh, "install -d -m 0755 /etc/homelab")
    files = (
        ("homelab-ephemeral-runner.sh", "/usr/local/sbin/homelab-ephemeral-runner.sh", 0o755),
        ("homelab-ephemeral-runner@.service", "/etc/systemd/system/homelab-ephemeral-runner@.service", 0o644),
    )
    conf = (
        f'GITHUB_REPO="{GITHUB_REPO}"\n'
        'RUNNER_NAME_PREFIX="pve-runner"\n'
        f'RUNNER_LABELS="{RUNNER_LABELS}"\n'
    ).encode()
    uploads = []
    for name, remote, mode in files:
        with open(os.path.join(SUPERVISOR_SRC, name), "rb") as src:
            uploads.append((src.read().replace(b"\r\n", b"\n"), remote, mode))
    uploads.append((conf, f"/etc/homelab/ephemeral-runner-{CT_ID}.conf", 0o644))
    sftp = ssh.open_sftp()
    try:
        for data, remote, mode in uploads:
            with sftp.open(remote, "wb") as f:
                f.write(data)
            sftp.chmod(remote, mode)
    finally:
        sftp.close()
    exec_ssh(ssh, "systemctl daemon-reload")

    env_state = exec_ssh(ssh, f"if [ -f {SUPERVISOR_ENV} ]; then echo present; else echo missing; fi")
    if env_state == "present":
        exec_ssh(ssh, f"systemctl enable --now {SUPERVISOR_UNIT}")
        print(f"[+] {SUPERVISOR_UNIT} enabled and started.")
    else:
        print(f"[!] {SUPERVISOR_ENV} not found; supervisor installed but NOT enabled.")
        print("    Owner step: as root on the PVE host create that file (mode 0600) containing")
        print("    GITHUB_RUNNER_ADMIN_TOKEN='<fine-grained token, this repository only, Administration read/write>',")
        print(f"    then run: systemctl enable --now {SUPERVISOR_UNIT}")

def main():
    token = None if EPHEMERAL else get_runner_registration_token()
    runner_ver = get_latest_runner_version()

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)
    print(f"[+] Connected to Proxmox VE Host ({PVE_HOST})")

    if EPHEMERAL:
        exec_ssh(ssh, f"systemctl stop {SUPERVISOR_UNIT} 2>/dev/null || true")

    # 1. Check if CT 102 exists
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
                f"--memory 2048 "
                f"--swap 512 "
                f"--rootfs local-lvm:12 "
                f"--ostype debian "
                f"--unprivileged 0 "
                f"--features nesting=1,keyctl=1 "
                f"--onboot 1 --startup order=2,up=15 "
                f"--net0 name=eth0,bridge=vmbr1,ip=10.99.20.101/24,gw=10.99.20.1 "
                f"--nameserver '1.1.1.1 8.8.8.8' "
                f"--start 1"
            )
            exec_ssh(ssh, create_cmd)
            time.sleep(5)
            exec_ssh(ssh, f"pct exec {CT_ID} -- ping -c 3 1.1.1.1")

    # 2. Update / Install Runner v{runner_ver} inside CT
    print(f"\n[*] Ensuring Runner v{runner_ver} and dependencies inside CT {CT_ID}...")
    setup_script = f"""#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

# Check if docker and dotnet are present
if ! command -v docker &>/dev/null || ! command -v dotnet &>/dev/null; then
    apt-get update -y
    apt-get install -y --no-install-recommends \\
        ca-certificates curl gnupg lsb-release git jq sudo build-essential \\
        docker.io wget libicu-dev

    wget -q https://dot.net/v1/dotnet-install.sh -O /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet

    systemctl enable --now docker
fi

# Ensure runner user
if ! id "runner" &>/dev/null; then
    useradd -m -s /bin/bash runner
fi

# Revoke any legacy runner privileges
sed -i '/^runner ALL=/d' /etc/sudoers
rm -f /etc/sudoers.d/99-runner
gpasswd -d runner sudo 2>/dev/null || true
gpasswd -d runner docker 2>/dev/null || true

# Setup Runner Directory
RUNNER_DIR="/home/runner/actions-runner"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

RUNNER_ARCH="x64"
RUNNER_TAR="actions-runner-linux-${{RUNNER_ARCH}}-{runner_ver}.tar.gz"

# Check if target runner version already extracted
if [ ! -f "version_{runner_ver}.ok" ]; then
    echo "Downloading and extracting Runner v{runner_ver}..."
    # Stop any existing service
    ./svc.sh stop 2>/dev/null || true
    ./svc.sh uninstall 2>/dev/null || true
    rm -rf *
    curl -o "$RUNNER_TAR" -L "https://github.com/actions/runner/releases/download/v{runner_ver}/${{RUNNER_TAR}}"
    tar xzf "./$RUNNER_TAR"
    rm -f "./$RUNNER_TAR"
    ./bin/installdependencies.sh
    touch "version_{runner_ver}.ok"
fi

chown -R runner:runner /home/runner
"""
    if EPHEMERAL:
        setup_script += """
./svc.sh stop 2>/dev/null || true
./svc.sh uninstall 2>/dev/null || true
rm -f .runner .credentials .credentials_rsaparams
"""
    remote_script = exec_ssh(ssh, "mktemp")
    try:
        sftp = ssh.open_sftp()
        with sftp.open(remote_script, "w") as f:
            f.write(setup_script)
        sftp.close()

        exec_ssh(ssh, f"pct push {CT_ID} {remote_script} /root/setup-runner.sh --perms 0700")
        exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash /root/setup-runner.sh", timeout=600)
    finally:
        exec_ssh(ssh, f"rm -f {remote_script}")
        exec_ssh(ssh, f"pct exec {CT_ID} -- rm -f /root/setup-runner.sh || true")
    print(f"[+] Runner v{runner_ver} binary verified in CT {CT_ID}.")

    if EPHEMERAL:
        seal_and_install_supervisor(ssh)
        ssh.close()
        print("\n" + "=" * 60)
        print("  EPHEMERAL RUNNER PROVISIONING COMPLETED (UNVERIFIED)")
        print("=" * 60)
        return

    # 3. Configure and Register Runner
    print(f"\n[*] Registering Runner with GitHub ({GITHUB_REPO})...")
    config_cmd = (
        f"pct exec {CT_ID} -- su - runner -c '"
        f"cd /home/runner/actions-runner && "
        f"./config.sh --url https://github.com/{GITHUB_REPO} "
        f"--token {token} "
        f"--name pve-runner-01 "
        f"--labels self-hosted,linux,x64,proxmox,dotnet "
        f"--unattended --replace"
        f"'"
    )
    exec_ssh(ssh, config_cmd)
    print("[+] Runner registered with GitHub Actions!")

    # 4. Install and Start Runner Systemd Service
    print("\n[*] Installing Runner as a Systemd service...")
    exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash -c 'cd /home/runner/actions-runner && ./svc.sh install runner && ./svc.sh start'")
    print("[+] Runner systemd service started successfully!")

    # 5. Check Runner Service Status
    status = exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/bash -c 'cd /home/runner/actions-runner && ./svc.sh status'")
    print(f"\n[+] Service status:\n{status}")

    ssh.close()
    print("\n" + "=" * 60)
    print("  RUNNER PROVISIONING COMPLETED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    main()
