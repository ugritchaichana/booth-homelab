import os
import sys
import time
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = os.environ["PVE_PASS"]
minio_user = os.environ["MINIO_ROOT_USER"]
minio_pass = os.environ["MINIO_ROOT_PASSWORD"]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username="root", password=pve_pass, timeout=5)

cfg = f"""data_dirs="/var/lib/minio/data"
command_user="minio:minio"
supervisor=supervise-daemon

set -a
MINIO_ROOT_USER="{minio_user}"
MINIO_ROOT_PASSWORD="{minio_pass}"
MINIO_ADDRESS="0.0.0.0:9000"
MINIO_CONSOLE_ADDRESS="0.0.0.0:9001"
MINIO_BROWSER="on"
set +a
"""

_, out, _ = ssh.exec_command("mktemp")
host_conf = out.read().decode('utf-8').strip()
try:
    sftp = ssh.open_sftp()
    with sftp.open(host_conf, "w") as f:
        f.write(cfg)
    sftp.close()

    _, out, _ = ssh.exec_command(f"pct push 104 {host_conf} /etc/conf.d/minio --perms 0600")
    out.read()
finally:
    _, out, _ = ssh.exec_command(f"rm -f {host_conf}")
    out.read()

ssh.exec_command("pct exec 104 -- rc-update add minio default")
_, out, err = ssh.exec_command("pct exec 104 -- rc-service minio restart")
print("RC-SERVICE:\n" + out.read().decode('utf-8', errors='replace'))
print("ERR:\n" + err.read().decode('utf-8', errors='replace'))

time.sleep(2)
_, out, _ = ssh.exec_command("pct exec 104 -- curl -s -I http://127.0.0.1:9000/minio/health/live")
print("HEALTH:\n" + out.read().decode('utf-8', errors='replace'))

# Ensure mc alias symlink
ssh.exec_command("pct exec 104 -- ln -sf /usr/bin/minio-client /usr/bin/mc")

cmds = [
    f"mc alias set local http://127.0.0.1:9000 {minio_user} {minio_pass}",
    "mc mb --ignore-existing local/build-cache",
    "mc mb --ignore-existing local/test-artifacts",
    "mc ls local/"
]
for c in cmds:
    _, out, err = ssh.exec_command(f"pct exec 104 -- {c}")
    print(c, "->", out.read().decode('utf-8', errors='replace').strip())

# Check connectivity from Runner (CT 102) to MinIO (CT 104)
_, out, _ = ssh.exec_command("pct exec 102 -- curl -s -I http://10.99.20.20:9000/minio/health/live")
print("\nRunner (CT 102) -> MinIO (CT 104) Health:\n" + out.read().decode('utf-8', errors='replace'))

ssh.close()
