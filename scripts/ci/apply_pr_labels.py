#!/usr/bin/env python3
"""
Create repository labels and apply appropriate labels to Pull Requests in batch.
"""
import subprocess
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO = "ugritchaichana/booth-homelab"

LABELS = [
    ("area:billing", "1d76db", "Billing API and tax calculation domain"),
    ("area:order", "b60205", "Order API and checkout vouchers domain"),
    ("area:sdet", "0e8a16", "Automated testing, test runner, coverage"),
    ("ci/cd", "5319e7", "GitHub Actions runner, caching, CI pipeline"),
    ("performance", "fbca04", "Cache tuning, benchmarks, latency"),
    ("homelab", "0052cc", "Proxmox, Hyper-V, LXC, MinIO infrastructure"),
]

def run_cmd(cmd_str):
    return subprocess.run(cmd_str, shell=True, capture_output=True, text=True, encoding="utf-8", errors="replace")

def setup_labels():
    print("[*] Creating / verifying repository labels...", flush=True)
    for name, color, desc in LABELS:
        cmd = f'gh label create "{name}" --color "{color}" --description "{desc}" --repo {REPO}'
        res = run_cmd(cmd)
        if res.returncode == 0:
            print(f"    [+] Created label: '{name}'", flush=True)
        elif "already exists" in res.stderr.lower():
            print(f"    [=] Label already exists: '{name}'", flush=True)
        else:
            print(f"    [!] Note for label '{name}': {res.stderr.strip()}", flush=True)

def label_prs():
    print("[*] Batch labeling PR #1...", flush=True)
    pr1_labels = ["enhancement", "area:billing", "area:sdet", "performance", "ci/cd"]
    add_flags = " ".join([f'--add-label "{lbl}"' for lbl in pr1_labels])
    res1 = run_cmd(f'gh pr edit 1 {add_flags} --repo {REPO}')
    print(f"    [✓] PR #1 response: {res1.stdout.strip() or 'Success'}", flush=True)

    print("[*] Batch labeling PR #2...", flush=True)
    pr2_labels = ["enhancement", "area:order", "area:sdet", "performance", "ci/cd"]
    add_flags2 = " ".join([f'--add-label "{lbl}"' for lbl in pr2_labels])
    res2 = run_cmd(f'gh pr edit 2 {add_flags2} --repo {REPO}')
    print(f"    [✓] PR #2 response: {res2.stdout.strip() or 'Success'}", flush=True)

if __name__ == "__main__":
    setup_labels()
    label_prs()
