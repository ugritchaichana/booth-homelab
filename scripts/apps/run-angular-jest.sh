#!/usr/bin/env bash
# ==============================================================================
# Ultra-Fast Angular Jest Unit Test Runner with S3 Cache for Proxmox LXC
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../apps/frontend" && pwd)"
MINIO_S3="http://10.99.20.20:9000"
NPM_CACHE_TARGET="minio/build-cache/npm/node_modules.tar.zst"

echo "=========================================================="
echo "      ANGULAR JEST UNIT TEST RUNNER (PROXMOX CT 103)      "
echo "=========================================================="
echo "Frontend Dir: $ROOT_DIR"
cd "$ROOT_DIR"

START_TIME=$(date +%s%N)

MC_BIN="$(command -v mc || echo '/usr/bin/mc')"

# 1. Restore node_modules from MinIO cache if available
if [ ! -d "node_modules" ]; then
    echo "==> node_modules missing. Checking MinIO S3 remote cache..."
    if $MC_BIN stat "$NPM_CACHE_TARGET" >/dev/null 2>&1; then
        echo "[CACHE HIT] Found node_modules cache on MinIO. Downloading..."
        $MC_BIN cp "$NPM_CACHE_TARGET" /tmp/node_modules.tar.zst
        tar -I "zstd -d -T0" -xf /tmp/node_modules.tar.zst -C "$ROOT_DIR"
        rm -f /tmp/node_modules.tar.zst
        echo "[OK] Restored node_modules from MinIO virtual bus."
    else
        echo "[CACHE MISS] Running npm install..."
        npm install --prefer-offline --no-audit --no-fund
        echo "==> Archiving node_modules to MinIO..."
        tar -I "zstd -T0 -3" -cf /tmp/node_modules.tar.zst node_modules
        $MC_BIN cp /tmp/node_modules.tar.zst "$NPM_CACHE_TARGET" || true
        rm -f /tmp/node_modules.tar.zst
    fi
fi

# 2. Execute Jest Tests
echo "==> Running Jest Unit Tests for Angular..."
npx jest --ci --colors --coverage

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo "=========================================================="
echo " [SUCCESS] Angular Jest Tests Completed in: ${DURATION_MS} ms"
echo "=========================================================="
