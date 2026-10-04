#!/bin/sh
set -eu

echo "==> [MinIO Provisioner] Waiting for MinIO service..."
until mc alias set myminio http://minio:9000 minioadmin minioadmin_secret; do
  echo "==> MinIO not ready yet. Retrying in 1 second..."
  sleep 1
done

echo "==> [MinIO Provisioner] Connected. Provisioning S3 Buckets..."
mc mb myminio/angular-nx-cache --ignore-existing
mc mb myminio/sdet-test-artifacts --ignore-existing

echo "==> [MinIO Provisioner] Setting 7-day ILM Expiration Rules..."
# Check and set ILM rule for angular-nx-cache
if ! mc ilm rule list myminio/angular-nx-cache 2>/dev/null | grep -q "Days: 7"; then
  mc ilm rule add myminio/angular-nx-cache --expire-days 7 || true
fi

# Check and set ILM rule for sdet-test-artifacts
if ! mc ilm rule list myminio/sdet-test-artifacts 2>/dev/null | grep -q "Days: 7"; then
  mc ilm rule add myminio/sdet-test-artifacts --expire-days 7 || true
fi

echo "==> [MinIO Provisioner] Registering IAM Policies (CREEP CVE-2025-36852 Mitigated)..."
mc admin policy create myminio nx-pr-ro /policies/nx-pr-ro.json || true
mc admin policy create myminio nx-main-rw /policies/nx-main-rw.json || true
mc admin policy create myminio artifacts-rw /policies/artifacts-rw.json || true

echo "==> [MinIO Provisioner] Creating Scoped Service Users..."
mc admin user add myminio gha-pr-runner StrongPRSecretKey123 || true
mc admin user add myminio gha-main-builder StrongMainSecretKey123 || true
mc admin user add myminio sdet-reporter StrongReporterSecretKey123 || true

echo "==> [MinIO Provisioner] Attaching Scoped Policies to Users..."
mc admin policy attach myminio nx-pr-ro --user gha-pr-runner
mc admin policy attach myminio nx-main-rw --user gha-main-builder
mc admin policy attach myminio artifacts-rw --user sdet-reporter

echo "==> [MinIO Provisioner] MinIO S3 Sandbox successfully initialized and hardened."
exit 0
