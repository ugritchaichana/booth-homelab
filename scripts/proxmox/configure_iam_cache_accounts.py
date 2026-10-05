import os
import sys
import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = os.environ["PVE_PASS"]
minio_root_user = os.environ["MINIO_ROOT_USER"]
minio_root_pass = os.environ["MINIO_ROOT_PASSWORD"]

reader_user = os.environ.get("SDET_PR_READER_USER", "sdet_pr_reader")
reader_pass = os.environ.get("SDET_PR_READER_PASS", "PrReaderSecurePass2026!#")
writer_user = os.environ.get("SDET_CI_WRITER_USER", "sdet_ci_writer")
writer_pass = os.environ.get("SDET_CI_WRITER_PASS", "CiWriterSecurePass2026!#")

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username="root", password=pve_pass, timeout=10)

def run(cmd):
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    status = stdout.channel.recv_exit_status()
    print(f"[*] {cmd} -> (exit {status})")
    if out:
        print(f"    STDOUT: {out}")
    if err:
        print(f"    STDERR: {err}")
    return status, out, err

print("=== 1. Configure Admin Alias on CT 102 ===")
run(f"pct exec 102 -- mc alias set minio-admin http://10.99.20.20:9000 {minio_root_user} {minio_root_pass}")

print("=== 2. Remove Anonymous Access from Buckets ===")
run("pct exec 102 -- mc anonymous set none minio-admin/build-cache")
run("pct exec 102 -- mc anonymous set none minio-admin/test-artifacts")

print("=== 3. Provision Scoped IAM Users on MinIO ===")
run(f"pct exec 102 -- mc admin user add minio-admin {reader_user} {reader_pass}")
run(f"pct exec 102 -- mc admin policy attach minio-admin readonly --user {reader_user}")

run(f"pct exec 102 -- mc admin user add minio-admin {writer_user} {writer_pass}")
run(f"pct exec 102 -- mc admin policy attach minio-admin readwrite --user {writer_user}")

print("=== 4. Configure Runner User Aliases on CT 102 and CT 103 ===")
# CT 102: default 'minio' is PR reader (RO)
run(f"pct exec 102 -- su - runner -c 'mc alias set minio http://10.99.20.20:9000 {reader_user} {reader_pass}'")
# CT 102: 'minio-writer' is CI writer (RW)
run(f"pct exec 102 -- su - runner -c 'mc alias set minio-writer http://10.99.20.20:9000 {writer_user} {writer_pass}'")

# CT 103: default 'minio' is PR reader (RO)
run(f"pct exec 103 -- su - runner -c 'mc alias set minio http://10.99.20.20:9000 {reader_user} {reader_pass}'")
run(f"pct exec 103 -- su - runner -c 'mc alias set minio-writer http://10.99.20.20:9000 {writer_user} {writer_pass}'")

# Remove admin alias from runner container
run("pct exec 102 -- mc alias remove minio-admin")

ssh.close()
print("=== IAM Provisioning Complete ===")
