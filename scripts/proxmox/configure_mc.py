import sys
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect("100.121.209.85", username="root", password="12345678", timeout=5)

cmds = [
    "pct exec 102 -- /usr/bin/mc alias set minio http://10.99.20.20:9000 minioadmin minioadmin",
    "pct exec 102 -- /usr/bin/mc mb --ignore-existing minio/build-cache",
    "pct exec 102 -- /usr/bin/mc mb --ignore-existing minio/test-artifacts",
    "pct exec 102 -- /usr/bin/mc ls minio",
    "pct exec 102 -- su - runner -c '/usr/bin/mc alias set minio http://10.99.20.20:9000 minioadmin minioadmin'",
    "pct exec 102 -- su - runner -c '/usr/bin/mc ls minio'"
]
for c in cmds:
    _, out, err = ssh.exec_command(c)
    print(c, "->", out.read().decode('utf-8', errors='replace').strip())

ssh.close()
