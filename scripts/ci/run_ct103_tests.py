import os
import paramiko
import sys

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = os.environ["PVE_PASS"]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username='root', password=pve_pass, timeout=10)

cmd = "pct exec 103 -- su - runner -c 'cd /home/runner/actions-runner/_work/booth-homelab/booth-homelab/apps/frontend && npm test'"
_, stdout, stderr = ssh.exec_command(cmd)

out = stdout.read().decode('utf-8', errors='replace')
err = stderr.read().decode('utf-8', errors='replace')
ssh.close()

print("STDOUT:\n" + out)
if err:
    print("STDERR:\n" + err)
