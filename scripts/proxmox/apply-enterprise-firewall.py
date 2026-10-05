#!/usr/bin/env python3
"""
Enterprise Zero-Trust Firewall Provisioner for SDET Homelab (Proxmox VE 8.4)
Enforces:
1. Layer 2 Bridge Port Isolation: Runners cannot communicate with each other (Drop at kernel bridge)
2. Layer 3/4 Stateful Inspection: Default Deny egress (logged), whitelist HTTPS (443), HTTP (80), NTP (123)
3. Domain-based egress: runner DNS is redirected to a host dnsmasq that fills ipset ci-allowed-egress per domain
4. Internal Storage Whitelist: Allow access only to MinIO S3 API (port 9000), block Console (9001) from runners
5. Block Lateral Movement & Arbitrary Egress (SSH, SMTP, C2, high ports dropped, IPv6 dropped)
"""
import paramiko
import sys
from pathlib import Path

import yaml

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

import os

PVE_HOST = os.environ.get("PVE_HOST", "100.121.209.85")
PVE_USER = os.environ.get("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]

GATEWAY_IP = "10.99.20.1"
# Single source of truth for the domain list, upstream DNS, ipset timeout and log prefix
DEFAULTS_FILE = Path(__file__).resolve().parents[2] / "iac/ansible/roles/enterprise_firewall/defaults/main.yml"
CFG = yaml.safe_load(DEFAULTS_FILE.read_text(encoding="utf-8"))
ALLOWED_DOMAINS = CFG["egress_allowed_domains"]
UPSTREAM_DNS = CFG["egress_upstream_dns"]
IPSET_TIMEOUT = str(CFG["egress_ipset_timeout"])
DENY_LOG_PREFIX = CFG["egress_deny_log_prefix"]

DNSMASQ_CONF_PATH = "/etc/homelab-egress/dnsmasq.conf"
DNS_UNIT_NAME = "homelab-egress-dns.service"

FIREWALL_BASH_SCRIPT = """#!/usr/bin/env bash
# ==============================================================================
# Big Tech Enterprise-Grade Zero-Trust Firewall & Isolation for SDET Homelab
# ==============================================================================
set -euo pipefail

RUNNER_NET="10.99.20.0/24"
BRIDGE="vmbr1"
GW_IP="10.99.20.1"
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

# 3. Host Ingress Protection (Block runners from accessing host SSH :22 and PVE API :8006)
iptables -N HOMELAB-INPUT 2>/dev/null || iptables -F HOMELAB-INPUT
iptables -D INPUT -j HOMELAB-INPUT 2>/dev/null || true
iptables -I INPUT 1 -j HOMELAB-INPUT
iptables -A HOMELAB-INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A HOMELAB-INPUT -i "$BRIDGE" -s "$RUNNER_NET" -d "$GW_IP" -p udp --dport 53 -j ACCEPT
iptables -A HOMELAB-INPUT -i "$BRIDGE" -s "$RUNNER_NET" -d "$GW_IP" -p tcp --dport 53 -j ACCEPT
iptables -A HOMELAB-INPUT -s "$RUNNER_NET" -p tcp -m multiport --dports 22,8006 \
    -j REJECT --reject-with icmp-port-unreachable

# 4. Layer 3/4 Stateful Zero-Trust Chain
iptables -N HOMELAB-FORWARD 2>/dev/null || iptables -F HOMELAB-FORWARD

# Domain-fed egress ipset (entries are added by the egress resolver, never by this script)
ipset_header=$(ipset list -t ci-allowed-egress 2>/dev/null || true)
if [[ -n "$ipset_header" && "$ipset_header" != *timeout* ]]; then
    ipset destroy ci-allowed-egress
fi
ipset create -exist ci-allowed-egress hash:ip timeout @@IPSET_TIMEOUT@@

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

# Internet Egress: NTP and Domain-Scoped Package/API Repos (DNS is redirected to the host resolver)
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p udp --dport 123 -j ACCEPT
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p icmp --icmp-type echo-request -j ACCEPT

# Scoped 80/443 egress via ci-allowed-egress ipset
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -p tcp -m multiport --dports 80,443 -m set --match-set ci-allowed-egress dst -j ACCEPT

# Log, then Default Deny: Drop all unauthorized egress traffic (SSH 22, Telnet, C2, high ports)
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -m limit --limit 10/min --limit-burst 20 -j LOG --log-prefix "@@LOG_PREFIX@@ " --log-level 4
iptables -A HOMELAB-FORWARD -s "$RUNNER_NET" -j DROP

# Force runner DNS through the host resolver
if ip -4 -o addr show dev "$BRIDGE" 2>/dev/null | grep -q " $GW_IP/"; then
    for proto in udp tcp; do
        if ! iptables -t nat -C PREROUTING -i "$BRIDGE" -s "$RUNNER_NET" ! -d "$GW_IP" -p "$proto" --dport 53 -j DNAT --to-destination "$GW_IP:53" 2>/dev/null; then
            iptables -t nat -I PREROUTING 1 -i "$BRIDGE" -s "$RUNNER_NET" ! -d "$GW_IP" -p "$proto" --dport 53 -j DNAT --to-destination "$GW_IP:53"
        fi
    done
else
    echo "WARNING: $BRIDGE has no $GW_IP: runner DNS not redirected, runners have no DNS (fail-closed)" >&2
fi

# IPv6 is not provisioned for runners: drop it in both directions
if [ -e /proc/net/if_inet6 ]; then
    sysctl -w net.bridge.bridge-nf-call-ip6tables=1 >/dev/null 2>&1 || true
    for chain in INPUT FORWARD; do
        ip6tables -N "HOMELAB-${chain}6" 2>/dev/null || ip6tables -F "HOMELAB-${chain}6"
        ip6tables -A "HOMELAB-${chain}6" -j DROP
        if ! ip6tables -C "$chain" -i "$BRIDGE" -j "HOMELAB-${chain}6" 2>/dev/null; then
            ip6tables -I "$chain" 1 -i "$BRIDGE" -j "HOMELAB-${chain}6"
        fi
    done
fi

# 5. Port Forwarding for MinIO S3 API & Console (PREROUTING & Localhost OUTPUT)
iptables -t nat -C PREROUTING -p tcp --dport 9001 -j DNAT --to-destination 10.99.20.20:9001 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp --dport 9001 -j DNAT --to-destination 10.99.20.20:9001
iptables -t nat -C PREROUTING -p tcp --dport 9000 -j DNAT --to-destination 10.99.20.20:9000 2>/dev/null || \
    iptables -t nat -A PREROUTING -p tcp --dport 9000 -j DNAT --to-destination 10.99.20.20:9000

iptables -t nat -C OUTPUT -p tcp -o lo --dport 9001 -j DNAT --to-destination 10.99.20.20:9001 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp -o lo --dport 9001 -j DNAT --to-destination 10.99.20.20:9001

echo "[OK] Enterprise Zero-Trust Firewall Rules applied successfully."
""".replace("@@IPSET_TIMEOUT@@", IPSET_TIMEOUT).replace("@@LOG_PREFIX@@", DENY_LOG_PREFIX)


def render_dnsmasq_conf():
    lines = [
        "# Auto-generated by apply-enterprise-firewall.py - runner egress resolver (role: enterprise_firewall)",
        "port=53",
        f"listen-address={GATEWAY_IP}",
        "bind-dynamic",
        "user=nobody",
        "group=nogroup",
        "no-resolv",
        "no-hosts",
        "no-poll",
        "cache-size=0",
        "filter-AAAA",
    ]
    lines += [f"server={server}" for server in UPSTREAM_DNS]
    lines += [f"ipset=/{domain}/ci-allowed-egress" for domain in ALLOWED_DOMAINS]
    return "\n".join(lines) + "\n"


def render_dns_unit():
    return f"""[Unit]
Description=Homelab runner egress resolver (feeds ipset ci-allowed-egress)
After=network.target

[Service]
Type=simple
ExecStartPre=-/usr/sbin/ipset create -exist ci-allowed-egress hash:ip timeout {IPSET_TIMEOUT}
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --pid-file=/run/homelab-egress-dns.pid --conf-file={DNSMASQ_CONF_PATH}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
"""


def run(ssh, cmd, check=True):
    _, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode(errors="replace").strip()
    err = stderr.read().decode(errors="replace").strip()
    code = stdout.channel.recv_exit_status()
    if check and code != 0:
        raise SystemExit(f"[FATAL] `{cmd}` exited {code}: {err or out}")
    return out, err


def put(ssh, remote_path, text):
    sftp = ssh.open_sftp()
    with sftp.open(remote_path, "w") as f:
        f.write(text.replace("\r\n", "\n"))
    sftp.close()


def main():
    print(f"[*] Connecting to Proxmox VE Host ({PVE_HOST})...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)

    # 1. Egress resolver: packages, config, unit; it must run before DNS is redirected to it
    print("[*] Installing dnsmasq-base, ipset, iptables...")
    run(ssh, "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dnsmasq-base ipset iptables")
    run(ssh, "mkdir -p /etc/homelab-egress")
    print(f"[*] Writing resolver config to {DNSMASQ_CONF_PATH} ({len(ALLOWED_DOMAINS)} domains)...")
    put(ssh, DNSMASQ_CONF_PATH, render_dnsmasq_conf())
    run(ssh, f"/usr/sbin/dnsmasq --test --conf-file={DNSMASQ_CONF_PATH}")
    put(ssh, f"/etc/systemd/system/{DNS_UNIT_NAME}", render_dns_unit())
    run(ssh, f"systemctl daemon-reload && systemctl enable {DNS_UNIT_NAME} && systemctl restart {DNS_UNIT_NAME}")
    run(ssh, f"sleep 1 && systemctl is-active --quiet {DNS_UNIT_NAME}")
    print("[+] Egress resolver active.")

    # 2. Push firewall script
    remote_path = "/usr/local/bin/apply-homelab-firewall.sh"
    print(f"[*] Writing firewall script to {remote_path}...")
    put(ssh, remote_path, FIREWALL_BASH_SCRIPT)
    run(ssh, f"chmod +x {remote_path}")

    # 3. Persist br_netfilter in sysctl and modules
    print("[*] Persisting bridge netfilter settings...")
    run(ssh, "echo br_netfilter > /etc/modules-load.d/br_netfilter.conf")
    run(ssh, "printf 'net.bridge.bridge-nf-call-iptables = 1\\nnet.bridge.bridge-nf-call-ip6tables = 1\\n' > /etc/sysctl.d/99-bridge-firewall.conf")

    # 4. Execute script
    print("[*] Executing firewall script on Proxmox VE...")
    out, err = run(ssh, remote_path)
    print(out)
    if err:
        print("[STDERR]", err)

    # 5. Create persistent systemd service
    systemd_unit = f"""[Unit]
Description=Apply Enterprise Zero-Trust Firewall & Isolation for SDET Homelab
After=network.target network-online.target pve-cluster.service {DNS_UNIT_NAME}
Wants=network-online.target {DNS_UNIT_NAME}

[Service]
Type=oneshot
ExecStart=/usr/local/bin/apply-homelab-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""
    print("[*] Installing systemd service: homelab-firewall.service...")
    put(ssh, "/etc/systemd/system/homelab-firewall.service", systemd_unit)
    run(ssh, "systemctl daemon-reload && systemctl enable homelab-firewall.service")
    print("[+] Systemd service enabled for persistent boot-time protection.")

    ssh.close()
    print("[✓] Provisioning complete!")

if __name__ == "__main__":
    main()
