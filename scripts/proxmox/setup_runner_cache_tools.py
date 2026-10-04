import sys
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("100.121.209.85", username="root", password="12345678", timeout=5)

setup_cmds = [
    "apt-get update -y && apt-get install -y zstd",
    "wget -q https://dl-cdn.alpinelinux.org/alpine/v3.23/community/x86_64/minio-client-0.20250813.083541-r7.apk 2>/dev/null || true",
    "curl -s https://dl.min.io/client/mc/release/linux-amd64/mc -o /usr/local/bin/mc 2>/dev/null || true"
]

# Install mc from CT 104 (copy binary directly over SSH between CTs)
copy_mc = """
pct exec 104 -- cat /usr/bin/minio-client > /tmp/mc
pct push 102 /tmp/mc /usr/local/bin/mc
pct exec 102 -- chmod +x /usr/local/bin/mc
pct exec 102 -- apt-get update -y && pct exec 102 -- apt-get install -y zstd time
pct exec 102 -- su - runner -c "mc alias set minio http://10.99.20.20:9000 minioadmin minioadmin"
"""

for line in copy_mc.strip().splitlines():
    line = line.strip()
    if not line:
        continue
    _, out, err = ssh.exec_command(line)
    print(f"[EXEC] {line} -> {out.read().decode('utf-8', errors='replace').strip()}")

_, out, _ = ssh.exec_command("pct exec 102 -- su - runner -c 'mc ls minio/'")
print("\n[PASS] Runner MC test:\n" + out.read().decode('utf-8', errors='replace'))

ssh.close()
