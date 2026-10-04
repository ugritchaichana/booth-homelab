#!/usr/bin/env python3
"""
Automated Proxmox VE 8.x Configuration and AI Foundation Engine.
1. Removes "No valid subscription" nag dialog.
2. Updates PVE Appliance template list (pveam update).
3. Downloads essential templates: debian-12-standard and alpine-3.20-default.
4. Generates an API Token for AI Agent (root@pam!ai_token) with full Administrator permissions.
"""

import sys
import paramiko

PVE_HOST = "100.121.209.85"
PVE_USER = "root"
PVE_PASS = "12345678"

def run_cmd(ssh, cmd, ignore_error=False):
    print(f"\n==> [EXEC] {cmd}")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    code = stdout.channel.recv_exit_status()
    if out:
        print(f"[STDOUT]\n{out}")
    if err and code != 0:
        print(f"[STDERR]\n{err}")
        if not ignore_error:
            raise RuntimeError(f"Command failed with code {code}: {cmd}")
    return out

def main():
    print("=" * 60)
    print("  Proxmox VE Auto-Configuration & AI Foundation Setup")
    print("=" * 60)
    print(f"Connecting to Proxmox Node at {PVE_HOST}...")

    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)
    print("[PASS] Connected via SSH over Tailscale.")

    # 1. Disable Subscription Nag
    print("\n--- Step 1: Disabling No-Subscription Nag Dialog ---")
    sed_cmd = r"sed -Ezi.bak 's/(Ext.Msg.show\(\{\s+title: gettext\('\''No valid sub)/void\(\{ \/\/\1/g' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js && systemctl restart pveproxy.service"
    run_cmd(ssh, sed_cmd)
    print("[PASS] Subscription nag disabled.")

    # 2. Update Template Index
    print("\n--- Step 2: Updating Appliance Template Index ---")
    run_cmd(ssh, "pveam update")
    print("[PASS] Appliance list updated.")

    # 3. Download Templates (Debian 12 and Alpine 3.20)
    print("\n--- Step 3: Downloading LXC Templates to 'local' storage ---")
    avail = run_cmd(ssh, "pveam available --section system")
    
    # Find latest debian-12
    debian_tmpl = None
    alpine_tmpl = None
    for line in avail.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            tmpl_name = parts[1]
            if "debian-12-standard" in tmpl_name and not debian_tmpl:
                debian_tmpl = tmpl_name
            if "alpine-3.20-default" in tmpl_name and not alpine_tmpl:
                alpine_tmpl = tmpl_name

    print(f"Target Debian Template: {debian_tmpl}")
    print(f"Target Alpine Template: {alpine_tmpl}")

    # Check already downloaded templates
    existing = run_cmd(ssh, "pveam list local")
    
    if debian_tmpl and debian_tmpl not in existing:
        print(f"Downloading {debian_tmpl}...")
        run_cmd(ssh, f"pveam download local {debian_tmpl}")
    else:
        print(f"{debian_tmpl} already present in local storage.")

    if alpine_tmpl and alpine_tmpl not in existing:
        print(f"Downloading {alpine_tmpl}...")
        run_cmd(ssh, f"pveam download local {alpine_tmpl}")
    else:
        print(f"{alpine_tmpl} already present in local storage.")

    # 4. Generate AI Agent API Token for Proxmox REST API
    print("\n--- Step 4: Provisioning AI Agent Proxmox API Token ---")
    # Check if token exists
    tokens = run_cmd(ssh, "pveum user token list root@pam", ignore_error=True)
    if "ai_agent" not in tokens:
        print("Creating API Token 'ai_agent' for root@pam...")
        token_output = run_cmd(ssh, "pveum user token add root@pam ai_agent --privsep 0 --output-format json")
        print(f"API Token Created: {token_output}")
    else:
        print("API Token 'ai_agent' already exists.")

    ssh.close()
    print("\n" + "=" * 60)
    print("  ALL AUTO-CONFIGURATION TASKS COMPLETED SUCCESSFULLY!")
    print("=" * 60)

if __name__ == "__main__":
    main()
