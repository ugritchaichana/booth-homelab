import os
import sys
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = os.environ["PVE_PASS"]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username="root", password=pve_pass, timeout=5)

setup_cmds = [
    "apt-get update -y && apt-get install -y zstd",
    "wget -q https://dl-cdn.alpinelinux.org/alpine/v3.23/community/x86_64/minio-client-0.20250813.083541-r7.apk 2>/dev/null || true",
    "curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc 2>/dev/null || true"
]

def run(cmd):
    _, out, _ = ssh.exec_command(cmd)
    text = out.read().decode('utf-8', errors='replace').strip()
    print(f"[EXEC] {cmd} -> {text}")
    return text


# Install mc from CT 104 (copy binary directly over SSH between CTs)
host_tmp = run("mktemp")
try:
    run(f"pct exec 104 -- cat /usr/bin/minio-client > {host_tmp}")
    run(f"pct push 102 {host_tmp} /usr/local/bin/mc")
finally:
    run(f"rm -f {host_tmp}")
run("pct exec 102 -- chmod +x /usr/local/bin/mc")
run("pct exec 102 -- apt-get update -y && pct exec 102 -- apt-get install -y zstd time")

print("\n[PASS] Runner MC version:\n" + run("pct exec 102 -- mc --version"))

ssh.close()
