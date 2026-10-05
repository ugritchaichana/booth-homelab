import os
import sys
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

cmds = [
    f"pct exec 102 -- /usr/bin/mc alias set minio http://10.99.20.20:9000 {minio_user} {minio_pass}",
    "pct exec 102 -- /usr/bin/mc mb --ignore-existing minio/build-cache",
    "pct exec 102 -- /usr/bin/mc mb --ignore-existing minio/test-artifacts",
    "pct exec 102 -- /usr/bin/mc ls minio",
    f"pct exec 102 -- su - runner -c '/usr/bin/mc alias set minio http://10.99.20.20:9000 {minio_user} {minio_pass}'",
    "pct exec 102 -- su - runner -c '/usr/bin/mc ls minio'"
]
for c in cmds:
    _, out, err = ssh.exec_command(c)
    print(c, "->", out.read().decode('utf-8', errors='replace').strip())

ssh.close()
