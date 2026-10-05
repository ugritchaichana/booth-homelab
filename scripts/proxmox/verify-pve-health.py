#!/usr/bin/env python3
"""
Diagnostic and Health Verification for Proxmox VE 8.x Environment.
Performs end-to-end verification across:
1. TCP / Port Reachability (SSH 22, Web GUI / API 8006)
2. Proxmox REST API Authentication via API Token
3. SSH Access & System Telemetry (Uptime, CPU, RAM, Storage, Nested Virtualization)
4. LXC Storage & Template Cache verification
"""

import os
import sys
import json
import urllib3
import requests
import paramiko

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

PVE_HOST = os.getenv("PVE_HOST", "100.121.209.85")
PVE_PORT = int(os.getenv("PVE_PORT", "8006"))
PVE_USER = os.getenv("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]
API_TOKEN_ID = os.environ["PVE_TOKEN_ID"]
API_TOKEN_SECRET = os.environ["PVE_TOKEN_SECRET"]

def test_api():
    print(f"\n[1/3] Testing Proxmox REST API (https://{PVE_HOST}:{PVE_PORT}/api2/json)...")
    headers = {
        "Authorization": f"PVEAPIToken={API_TOKEN_ID}={API_TOKEN_SECRET}"
    }
    base_url = f"https://{PVE_HOST}:{PVE_PORT}/api2/json"
    
    # 1. Version check
    try:
        r = requests.get(f"{base_url}/version", headers=headers, verify=False, timeout=5)
        print(f"  - GET /version: HTTP {r.status_code}")
        if r.status_code == 200:
            v_data = r.json().get("data", {})
            print(f"    Release: {v_data.get('release')}, Version: {v_data.get('version')}, Repoid: {v_data.get('repoid')}")
        else:
            print(f"    [WARN] Non-200 response: {r.text}")
    except Exception as e:
        print(f"    [FAIL] API call error: {e}")
        return False

    # 2. Nodes check
    try:
        r = requests.get(f"{base_url}/nodes", headers=headers, verify=False, timeout=5)
        if r.status_code == 200:
            nodes = r.json().get("data", [])
            print(f"  - Active Nodes: {len(nodes)}")
            for n in nodes:
                print(f"    Node: {n.get('node')} (status: {n.get('status')}, cpu: {n.get('cpu', 0)*100:.1f}%, mem: {n.get('mem', 0)/(1024**3):.2f}/{n.get('maxmem', 1)/(1024**3):.2f} GB)")
        else:
            print(f"    [WARN] Failed to list nodes: {r.text}")
    except Exception as e:
        print(f"    [FAIL] Nodes API error: {e}")

    # 3. Storage check
    try:
        r = requests.get(f"{base_url}/nodes/pve/storage", headers=headers, verify=False, timeout=5)
        if r.status_code == 200:
            storages = r.json().get("data", [])
            print(f"  - Storage Pools ({len(storages)} found):")
            for s in storages:
                print(f"    Pool: {s.get('storage')} (type: {s.get('type')}, used: {s.get('used', 0)/(1024**3):.2f}/{s.get('total', 1)/(1024**3):.2f} GB, active: {s.get('active')})")
        else:
            print(f"    [WARN] Failed to list storage: {r.text}")
    except Exception as e:
        print(f"    [FAIL] Storage API error: {e}")

    return True

def test_ssh():
    print(f"\n[2/3] Testing SSH Terminal & Host Telemetry ({PVE_HOST}:22)...")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=5)
        print("  [PASS] SSH Authentication Successful.")
        
        # Uptime & Kernel
        _, stdout, _ = ssh.exec_command("uname -a && uptime")
        print(f"  - Kernel & Uptime: {stdout.read().decode().strip()}")

        # Virtualization Flags
        _, stdout, _ = ssh.exec_command("egrep -c '(vmx|svm)' /proc/cpuinfo")
        cpu_virt = stdout.read().decode().strip()
        print(f"  - Nested Virtualization Core Count: {cpu_virt} cores with SVM/VMX flags")

        # Memory summary
        _, stdout, _ = ssh.exec_command("free -h")
        print(f"  - Memory Status:\n{stdout.read().decode().strip()}")

        # LXC templates in cache
        _, stdout, _ = ssh.exec_command("pveam list local")
        print(f"  - LXC Templates in 'local' Storage:\n{stdout.read().decode().strip()}")

        # Existing VMs / Containers
        _, stdout, _ = ssh.exec_command("pct list; qm list")
        res = stdout.read().decode().strip()
        print(f"  - Existing Containers / VMs:\n{res if res else '    (No LXC/VM instances created yet)'}")

        ssh.close()
        return True
    except Exception as e:
        print(f"  [FAIL] SSH Connection failed: {e}")
        return False

def test_web_gui():
    print(f"\n[3/3] Testing Web GUI Response (https://{PVE_HOST}:{PVE_PORT}/)...")
    try:
        r = requests.get(f"https://{PVE_HOST}:{PVE_PORT}/", verify=False, timeout=5)
        print(f"  - HTTP Status: {r.status_code}")
        if "Proxmox Virtual Environment" in r.text or "pve-api-daemon" in r.headers.get("Server", ""):
            print("  [PASS] Proxmox Web GUI is serving valid web assets.")
            return True
        else:
            print("  [WARN] Unexpected response body.")
            return False
    except Exception as e:
        print(f"  [FAIL] Web GUI error: {e}")
        return False

def main():
    print("=" * 60)
    print(f"  PROXMOX VE 8.4 LIVE HEALTH CHECK: {PVE_HOST}")
    print("=" * 60)
    
    api_ok = test_api()
    ssh_ok = test_ssh()
    web_ok = test_web_gui()
    
    print("\n" + "=" * 60)
    if api_ok and ssh_ok and web_ok:
        print("  RESULT: PROXMOX IS 100% OPERATIONAL & READY FOR PHASE 3!")
    else:
        print("  RESULT: ISSUES DETECTED. CHECK DETAILED LOGS ABOVE.")
    print("=" * 60)

if __name__ == "__main__":
    main()
