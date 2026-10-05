#!/usr/bin/env python3
"""
Automated Verification Suite for Enterprise Zero-Trust Firewall (SDET Homelab)
Validates all 4 requirements with deterministic empirical tests.
"""
import paramiko
import sys
import time

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

import os

PVE_HOST = os.environ.get("PVE_HOST", "100.121.209.85")
PVE_USER = os.environ.get("PVE_USER", "root")
PVE_PASS = os.environ["PVE_PASS"]

def run_test(ssh, title, cmd, expect_success=True, timeout=10):
    print(f"\n[*] TESTING: {title}")
    _, stdout, stderr = ssh.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    code = stdout.channel.recv_exit_status()

    passed = (code == 0) if expect_success else (code != 0)
    status_str = "PASS" if passed else "FAIL"
    color_prefix = "\033[92m[✓ PASS]\033[0m" if passed else "\033[91m[✗ FAIL]\033[0m"

    print(f"    Command: {cmd}")
    print(f"    Exit Code: {code} (Expect Success: {expect_success}) -> {color_prefix}")
    if out:
        print(f"    Output: {out[:160]}")
    if err:
        print(f"    Stderr: {err[:160]}")
    return passed

def main():
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(PVE_HOST, username=PVE_USER, password=PVE_PASS, timeout=10)

    print("==========================================================")
    print("   ENTERPRISE ZERO-TRUST FIREWALL VERIFICATION SUITE      ")
    print("==========================================================")

    results = []

    # 1. Req 1: Runners CANNOT communicate with each other
    t1 = run_test(
        ssh,
        "Req 1: CT 102 (.NET) cannot ping CT 103 (Angular) [East-West Blocked]",
        "pct exec 102 -- ping -c 2 -W 1 10.99.20.103",
        expect_success=False
    )
    results.append(("CT 102 -> CT 103 (Blocked)", t1))

    t2 = run_test(
        ssh,
        "Req 1: CT 103 (Angular) cannot ping CT 102 (.NET) [East-West Blocked]",
        "pct exec 103 -- ping -c 2 -W 1 10.99.20.101",
        expect_success=False
    )
    results.append(("CT 103 -> CT 102 (Blocked)", t2))

    # 2. Req 2: Runners CAN read/write to MinIO S3 API (port 9000)
    t3 = run_test(
        ssh,
        "Req 2: CT 102 (.NET) can access MinIO S3 API (:9000)",
        "pct exec 102 -- curl -s -f -I http://10.99.20.20:9000/minio/health/live",
        expect_success=True
    )
    results.append(("CT 102 -> MinIO :9000 (Allowed)", t3))

    t4 = run_test(
        ssh,
        "Req 2: CT 103 (Angular) can access MinIO S3 API (:9000)",
        "pct exec 103 -- curl -s -f -I http://10.99.20.20:9000/minio/health/live",
        expect_success=True
    )
    results.append(("CT 103 -> MinIO :9000 (Allowed)", t4))

    t5 = run_test(
        ssh,
        "Req 2: CT 102 is BLOCKED from MinIO Admin Console (:9001)",
        "pct exec 102 -- curl -s -f -m 2 http://10.99.20.20:9001/",
        expect_success=False
    )
    results.append(("CT 102 -> MinIO Console :9001 (Blocked)", t5))

    # 3. Req 3: Restricted Internet Access (Whitelist Only)
    t6 = run_test(
        ssh,
        "Req 3: CT 102 allowed HTTPS (443) to GitHub API",
        "pct exec 102 -- curl -s -f -I https://api.github.com",
        expect_success=True
    )
    results.append(("CT 102 -> GitHub HTTPS :443 (Allowed)", t6))

    t7 = run_test(
        ssh,
        "Req 3: CT 103 allowed HTTPS (443) to npm Registry",
        "pct exec 103 -- curl -s -f -I https://registry.npmjs.org",
        expect_success=True
    )
    results.append(("CT 103 -> npm HTTPS :443 (Allowed)", t7))

    t8 = run_test(
        ssh,
        "Req 3: CT 102 BLOCKED on unauthorized outbound port (SSH port 22 to external)",
        "pct exec 102 -- curl -s -m 2 --connect-timeout 2 telnet://1.1.1.1:22",
        expect_success=False
    )
    results.append(("CT 102 -> Outbound SSH :22 (Dropped by Default Deny)", t8))

    t9 = run_test(
        ssh,
        "Req 3: CT 102 BLOCKED on unauthorized high port (TCP 8888)",
        "pct exec 102 -- curl -s -m 2 --connect-timeout 2 telnet://1.1.1.1:8888",
        expect_success=False
    )
    results.append(("CT 102 -> Outbound High Port :8888 (Dropped by Default Deny)", t9))

    # 4. Req 4: Host Ingress Protection (HOMELAB-INPUT)
    t11 = run_test(
        ssh,
        "Req 4: CT 102 BLOCKED from Host Proxmox API (:8006)",
        "pct exec 102 -- curl -k -s -m 2 https://10.99.20.1:8006/",
        expect_success=False
    )
    results.append(("CT 102 -> Host API :8006 (Blocked)", t11))

    t12 = run_test(
        ssh,
        "Req 4: CT 102 BLOCKED from Host SSH (:22)",
        "pct exec 102 -- curl -s -m 2 telnet://10.99.20.1:22",
        expect_success=False
    )
    results.append(("CT 102 -> Host SSH :22 (Blocked)", t12))

    t13 = run_test(
        ssh,
        "Req 3: CT 102 BLOCKED on arbitrary external IP on HTTPS :443 (Scoped Egress)",
        "pct exec 102 -- curl -k -s -m 2 --connect-timeout 2 https://1.1.1.1/",
        expect_success=False
    )
    results.append(("CT 102 -> Arbitrary IP :443 (Dropped by Scoped Egress)", t13))

    # 5. External Access Check: User PC still accesses MinIO Console (:9001)
    import urllib.request
    try:
        req = urllib.request.urlopen("http://100.121.209.85:9001", timeout=3)
        t10 = (req.status == 200)
    except Exception as ex:
        print("    [!] urllib test exception:", ex)
        t10 = False
    print(f"\n[*] TESTING: External Tailscale Client accesses MinIO Console (:9001) -> {'[✓ PASS]' if t10 else '[✗ FAIL]'}")
    results.append(("External Client -> MinIO Console :9001 (Preserved)", t10))

    ssh.close()

    print("\n==========================================================")
    print("                    EVALUATION SUMMARY                    ")
    print("==========================================================")
    all_passed = True
    for name, status in results:
        status_label = "[PASS]" if status else "[FAIL]"
        print(f" {status_label:<8} {name}")
        if not status:
            all_passed = False

    print("==========================================================")
    if all_passed:
        print(f" [SUCCESS] All {len(results)} Enterprise Zero-Trust Assertions PASSED!")
        sys.exit(0)
    else:
        print(" [ERROR] One or more assertions failed!")
        sys.exit(1)

if __name__ == "__main__":
    main()
