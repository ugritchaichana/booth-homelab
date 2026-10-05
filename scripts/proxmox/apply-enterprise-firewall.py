#!/usr/bin/env python3
"""
Enterprise Zero-Trust Firewall Provisioner for SDET Homelab (Proxmox VE 8.4)
Enforces:
1. Layer 2 Bridge Port Isolation: Runners cannot communicate with each other (Drop at kernel bridge)
2. Layer 3/4 Stateful Inspection: Default Deny egress, whitelist HTTPS (443), HTTP (80), DNS (53), NTP (123)
3. Internal Storage Whitelist: Allow access only to MinIO S3 API (port 9000), block Console (9001) from runners
4. Block Lateral Movement & Arbitrary Egress (SSH, SMTP, C2, high ports dropped)
"""
import paramiko
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

import os

PVE_HOST = os.environ.get("PVE_HOST", "100.121.209.85")
PVE_USER = os.environ.get("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]

FIREWALL_BASH_SCRIPT = """#!/usr/bin/env bash
# ==============================================================================
# Big Tech Enterprise-Grade Zero-Trust Firewall & Isolation for SDET Homelab
# ==============================================================================
set -euo pipefail

RUNNER_NET="10.99.20.0/24"
CT102_IP="10.99.20.101"
CT103_IP="10.99.20.103"
MINIO_IP="10.99.20.20"

# 1. Enable Bridge Netfilter so Layer 2 bridge frames traverse iptables
modprobe br_netfilter 2>/dev/null || true
sysctl -w net.bridge.bridge-nf-call-iptables=1 >/dev/null 2>&1 || true

# 2. Layer 2 Bridge Port Isolation (Drop runner-to-runner frames at kernel switch)
for iface in veth102i0 veth103i0; do
    if ip link show "$iface" >/dev/null 2>&1; then
        bridge link set dev "$iface" isolated on
    fi
done
if ip link show "veth104i0" >/dev/null 2>&1; then
    bridge link set dev "veth104i0" isolated off
fi

# 3. Layer 3/4 Stateful Zero-Trust Chain
iptables -N HOMELAB-FORWARD 2>/dev/null || iptables -F HOMELAB-FORWARD

iptables -D FORWARD -j HOMELAB-FORWARD 2>/dev/null || true
iptables -I FORWARD 1 -j HOMELAB-FORWARD

# Drop invalid packets
iptables -A HOMELAB-FORWARD -m state --state INVALID -j DROP

# Allow established and related connections (Return traffic)
iptables -A HOMELAB-FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# East-West Hard Block: Runners cannot communicate with each other (Defense-in-Depth L3)
iptables -A HOMELAB-FORWARD -s "$CT102_IP" -d "$CT103_IP" -j REJECT --reject-with icmp-host-prohibited
iptables -A HOMELAB-FORWARD -s "$CT103_IP" -d "$CT102_IP" -j REJECT --reject-with icmp-host-prohibited

# Storage Fabric Access (MinIO S3 API only)
iptables -A HOMELAB-FORWARD -s "$CT102_IP" -d "$MINIO_IP" -p tcp --dport 9000 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$CT103_IP" -d "$MINIO_IP" -p tcp --dport 9000 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -d "$MINIO_IP" -p icmp -j ACCEPT

# Block runners from accessing MinIO Console (:9001)
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -d "$MINIO_IP" -p tcp --dport 9001 -j REJECT --reject-with icmp-port-unreachable

# Internet Egress Whitelist (Strict Least Privilege)
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p udp --dport 53 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p tcp --dport 53 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p tcp --dport 443 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p tcp --dport 80 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p udp --dport 123 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p icmp --icmp-type echo-request -j ACCEPT

# Default Deny: Drop all unauthorized egress traffic (SSH 22, Telnet, C2, high ports)
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -j DROP

# 4. Port Forwarding for MinIO S3 API & Console (PREROUTING & Localhost OUTPUT)
iptables -t nat -C PREROUTING -p tcp --dport 9001 -j DNAT --to-destination 10.99.20.20:9001 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp --dport 9001 -j DNAT --to-destination 10.99.20.20:9001
iptables -t nat -C PREROUTING -p tcp --dport 9000 -j DNAT --to-destination 10.99.20.20:9000 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp --dport 9000 -j DNAT --to-destination 10.99.20.20:9000

iptables -t nat -C OUTPUT -p tcp -o lo --dport 9001 -j DNAT --to-destination 10.99.20.20:9001 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp -o lo --dport 9001 -j DNAT --to-destination 10.99.20.20:9001

echo "[OK] Enterprise Zero-Trust Firewall Rules applied successfully."
"""

def main():
    print(f"[*] Connecting to Proxmox VE Host ({PVE_HOST})...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)

    # 1. Push firewall script
    remote_path = "/usr/local/bin/apply-homelab-firewall.sh"
    print(f"[*] Writing firewall script to {remote_path}...")
    sftp = ssh.open_sftp()
    with sftp.open(remote_path, "w") as f:
        f.write(FIREWALL_BASH_SCRIPT.replace("\r\n", "\n"))
    sftp.close()

    ssh.exec_command(f"chmod +x {remote_path}")

    # 2. Persist br_netfilter in sysctl and modules
    print("[*] Persisting bridge netfilter settings...")
    ssh.exec_command("echo br_netfilter > /etc/modules-load.d/br_netfilter.conf")
    ssh.exec_command("echo 'net.bridge.bridge-nf-call-iptables = 1' > /etc/sysctl.d/99-bridge-firewall.conf")

    # 3. Execute script
    print("[*] Executing firewall script on Proxmox VE...")
    _, stdout, stderr = ssh.exec_command(remote_path)
    print(stdout.read().decode().strip())
    err = stderr.read().decode().strip()
    if err:
        print("[STDERR]", err)

    # 4. Create persistent systemd service
    systemd_unit = """[Unit]
Description=Apply Enterprise Zero-Trust Firewall & Isolation for SDET Homelab
After=network.target network-online.target pve-cluster.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-homelab-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""
    print("[*] Installing systemd service: homelab-firewall.service...")
    sftp = ssh.open_sftp()
    with sftp.open("/etc/systemd/system/homelab-firewall.service", "w") as f:
        f.write(systemd_unit.replace("\r\n", "\n"))
    sftp.close()

    ssh.exec_command("systemctl daemon-reload && systemctl enable homelab-firewall.service")
    print("[+] Systemd service enabled for persistent boot-time protection.")

    ssh.close()
    print("[✓] Provisioning complete!")

if __name__ == "__main__":
    main()
