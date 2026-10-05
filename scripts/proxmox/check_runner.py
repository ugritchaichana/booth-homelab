import os
import sys
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = os.environ["PVE_PASS"]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username='root', password=pve_pass, timeout=5)

cmd = "pct exec 102 -- bash -c 'which docker; which dotnet; docker --version; dotnet --version; ls -la /home/runner/actions-runner'"
_, stdout, stderr = ssh.exec_command(cmd)
print("STDOUT:\n" + stdout.read().decode('utf-8', errors='replace'))
print("STDERR:\n" + stderr.read().decode('utf-8', errors='replace'))
ssh.close()
