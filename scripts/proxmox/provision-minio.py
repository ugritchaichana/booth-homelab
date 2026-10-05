#!/usr/bin/env python3
"""
Automated Provisioning for CT 104 (minio-s3) on Proxmox VE 8.4.
Role: Enterprise S3 Remote Cache for CI/CD Runners.
Base: Alpine Linux 3.23
IP: 10.99.20.20/24 (vmbr1 DMZ)
Port: 9000 (API), 9001 (Console)
"""

import sys
import time
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

PVE_HOST = os.environ.get("PVE_HOST", "100.121.209.85")
PVE_USER = os.environ.get("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]
MINIO_USER = os.environ.get("MINIO_ROOT_USER", "minioadmin")
MINIO_PASS = os.environ["MINIO_ROOT_PASSWORD"]
CT_ID = "104"
CT_NAME = "minio-s3"
TEMPLATE = "local:vztmpl/alpine-3.23-default_20260116_amd64.tar.xz"

def exec_ssh(ssh, cmd, timeout=300):
    print(f"\n[PVE EXEC] {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    code = stdout.channel.recv_exit_status()
    if out:
        print(f"[STDOUT]\n{out}")
    if err and code != 0:
        print(f"[STDERR]\n{err}")
    if code != 0:
        raise RuntimeError(f"Command failed (code {code}): {cmd}")
    return out

def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)
    print(f"[+] Connected to Proxmox VE Host ({PVE_HOST})")

    # 1. Check if CT 104 exists
    check_ct = exec_ssh(ssh, f"pct status {CT_ID} 2>/dev/null || true")
    if "status:" in check_ct:
        print(f"[*] CT {CT_ID} already exists. Stopping and destroying for clean setup...")
        exec_ssh(ssh, f"pct stop {CT_ID} 2>/dev/null || true")
        time.sleep(2)
        exec_ssh(ssh, f"pct destroy {CT_ID} -force 1 -purge 1")

    # 2. Create CT 104
    print(f"\n[*] Creating Alpine LXC Container {CT_ID} ({CT_NAME})...")
    create_cmd = (
        f"pct create {CT_ID} {TEMPLATE} "
        f"--hostname {CT_NAME} "
        f"--cores 1 "
        f"--memory 512 "
        f"--swap 256 "
        f"--rootfs local-lvm:6 "
        f"--ostype alpine "
        f"--unprivileged 0 "
        f"--features nesting=1 "
        f"--net0 name=eth0,bridge=vmbr1,ip=10.99.20.20/24,gw=10.99.20.1 "
        f"--nameserver '1.1.1.1 8.8.8.8' "
        f"--start 1"
    )
    exec_ssh(ssh, create_cmd)
    print(f"[+] CT {CT_ID} created and started.")

    # 3. Wait for network
    time.sleep(4)
    exec_ssh(ssh, f"pct exec {CT_ID} -- ping -c 3 1.1.1.1")
    print("[+] CT 104 Internet connectivity verified.")

    # 4. Install MinIO and OpenRC Service inside Alpine
    setup_script = f"""#!/bin/sh
set -e

apk update
apk add --no-cache curl wget ca-certificates bash

# Download MinIO Server and Client
mkdir -p /usr/local/bin /data/minio
echo "Downloading MinIO Server..."
wget -q https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

echo "Downloading MinIO Client (mc)..."
wget -q https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Create OpenRC Service
cat << EOF > /etc/init.d/minio
#!/sbin/openrc-run
name="minio"
description="MinIO Object Storage"
command="/usr/local/bin/minio"
command_args="server /data/minio --address :9000 --console-address :9001"
command_background=true
pidfile="/run/minio.pid"
export MINIO_ROOT_USER="{MINIO_USER}"
export MINIO_ROOT_PASSWORD="{MINIO_PASS}"

depend() {{
    need net
}}
EOF

chmod +x /etc/init.d/minio
rc-update add minio default
rc-service minio start

# Wait for MinIO to become healthy
echo "Waiting for MinIO startup..."
for i in $(seq 1 15); do
    if curl -s http://127.0.0.1:9000/minio/health/live; then
        echo "MinIO is LIVE!"
        break
    fi
    sleep 1
done

# Configure mc alias and buckets
/usr/local/bin/mc alias set local http://127.0.0.1:9000 {MINIO_USER} {MINIO_PASS}
/usr/local/bin/mc mb --ignore-existing local/build-cache
/usr/local/bin/mc mb --ignore-existing local/test-artifacts

# Set 7-day TTL retention rule
/usr/local/bin/mc ilm rule add --expire-days 7 local/build-cache
/usr/local/bin/mc ilm rule add --expire-days 7 local/test-artifacts
/usr/local/bin/mc ilm rule list local/build-cache
"""
    sftp = ssh.open_sftp()
    with sftp.open("/tmp/setup-minio.sh", "w") as f:
        f.write(setup_script)
    sftp.close()

    exec_ssh(ssh, "chmod +x /tmp/setup-minio.sh")
    exec_ssh(ssh, f"pct push {CT_ID} /tmp/setup-minio.sh /root/setup-minio.sh")
    exec_ssh(ssh, f"pct exec {CT_ID} -- /bin/sh /root/setup-minio.sh", timeout=300)
    print(f"[+] MinIO S3 Server successfully configured in CT {CT_ID}!")

    # 5. Verify from Runner (CT 102 -> CT 104 connectivity)
    print("\n[*] Verifying connectivity from Runner (CT 102) to MinIO (CT 104)...")
    res = exec_ssh(ssh, "pct exec 102 -- curl -s -I http://10.99.20.20:9000/minio/health/live")
    print(f"[+] Health check from CT 102:\n{res}")

    ssh.close()
    print("\n" + "=" * 60)
    print("  CT 104 (MINIO S3) PROVISIONING COMPLETE!")
    print("=" * 60)

if __name__ == "__main__":
    main()
