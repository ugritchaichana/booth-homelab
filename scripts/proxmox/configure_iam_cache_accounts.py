import os
import shlex
import sys
from pathlib import Path

import paramiko

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')


def require(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"[FAIL] required environment variable {name} is not set")
    return value


pve_host = os.environ.get("PVE_HOST", "100.121.209.85")
pve_pass = require("PVE_PASS")
minio_root_user = require("MINIO_ROOT_USER")
minio_root_pass = require("MINIO_ROOT_PASSWORD")

reader_user = os.environ.get("SDET_PR_READER_USER", "sdet_pr_reader")
reader_pass = require("SDET_PR_READER_PASS")
writer_user = os.environ.get("SDET_CI_WRITER_USER", "sdet_ci_writer")
writer_pass = require("SDET_CI_WRITER_PASS")

POLICY_DIR = Path(__file__).resolve().parents[2] / "iac" / "minio" / "policies"
ENDPOINT = "http://10.99.20.20:9000"
ADMIN = "minio-admin"
BUCKETS = ("build-cache", "test-artifacts")
SECRETS = sorted(
    {v for s in (pve_pass, minio_root_pass, reader_pass, writer_pass) for v in (s, shlex.quote(s))},
    key=len,
    reverse=True,
)

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(pve_host, username="root", password=pve_pass, timeout=10)


def mask(text):
    for secret in SECRETS:
        text = text.replace(secret, "***")
    return text


def run(cmd, check=True, ok_if=None):
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode('utf-8', errors='replace').strip()
    err = stderr.read().decode('utf-8', errors='replace').strip()
    status = stdout.channel.recv_exit_status()
    print(f"[*] {mask(cmd)} -> (exit {status})")
    if out:
        print(f"    STDOUT: {mask(out)}")
    if err:
        print(f"    STDERR: {mask(err)}")
    benign = ok_if is not None and ok_if in f"{out} {err}".lower()
    if check and status != 0 and not benign:
        raise RuntimeError(f"command failed (exit {status}): {mask(cmd)}")
    return status, out, err


def as_runner(ct, inner, check=True):
    return run(f"pct exec {ct} -- su - runner -c {shlex.quote(inner)}", check=check)


def put_policy(name, filename):
    body = (POLICY_DIR / filename).read_text(encoding="utf-8")
    _, host_tmp, _ = run("mktemp")
    try:
        _, ct_tmp, _ = run("pct exec 102 -- mktemp")
        try:
            sftp = ssh.open_sftp()
            with sftp.open(host_tmp, "w") as f:
                f.write(body)
            sftp.close()
            run(f"pct push 102 {host_tmp} {ct_tmp}")
            run(f"pct exec 102 -- mc admin policy create {ADMIN} {name} {ct_tmp}")
        finally:
            run(f"pct exec 102 -- rm -f {ct_tmp}", check=False)
    finally:
        run(f"rm -f {host_tmp}", check=False)


scoped_users = (
    (reader_user, reader_pass, "build-cache-reader", "readonly"),
    (writer_user, writer_pass, "build-cache-writer", "readwrite"),
)

try:
    print("=== 1. Configure Admin Alias on CT 102 (removed at the end) ===")
    run(f"pct exec 102 -- mc alias set {ADMIN} {ENDPOINT} {shlex.quote(minio_root_user)} {shlex.quote(minio_root_pass)}")

    print("=== 2. Keep Buckets Private ===")
    for bucket in BUCKETS:
        run(f"pct exec 102 -- mc mb --ignore-existing {ADMIN}/{bucket}")
        run(f"pct exec 102 -- mc anonymous set none {ADMIN}/{bucket}")

    print("=== 3. Create Bucket-Scoped Policies ===")
    put_policy("build-cache-reader", "build-cache-reader.json")
    put_policy("build-cache-writer", "build-cache-writer.json")

    print("=== 4. Provision Scoped IAM Users and Swap Built-in Policies ===")
    for user, password, policy, builtin in scoped_users:
        run(f"pct exec 102 -- mc admin user add {ADMIN} {shlex.quote(user)} {shlex.quote(password)}")
        run(f"pct exec 102 -- mc admin policy attach {ADMIN} {policy} --user {shlex.quote(user)}", ok_if="already")
        run(f"pct exec 102 -- mc admin policy detach {ADMIN} {builtin} --user {shlex.quote(user)}", check=False)

    print("=== 5. Runner User Gets the Reader Alias Only (CT 102, CT 103) ===")
    for ct in ("102", "103"):
        as_runner(ct, f"mc alias set minio {ENDPOINT} {shlex.quote(reader_user)} {shlex.quote(reader_pass)}")
        as_runner(ct, "mc alias remove minio-writer", check=False)
finally:
    run(f"pct exec 102 -- mc alias remove {ADMIN}", check=False)
    run("pct exec 102 -- mc alias remove minio", check=False)
    ssh.close()

print("=== IAM Provisioning Complete ===")
