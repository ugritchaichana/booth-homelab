#!/usr/bin/env bash
# ==============================================================================
# Ultra-Fast Angular Jest Unit Test Runner with S3 Cache for Proxmox LXC
# ==============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../apps/frontend" && pwd)"
MINIO_S3="http://10.99.20.20:9000"
NPM_CACHE_ROOT="minio/build-cache/npm"

echo "=========================================================="
echo "      ANGULAR JEST UNIT TEST RUNNER (PROXMOX CT 103)      "
echo "=========================================================="
echo "Frontend Dir: $ROOT_DIR"
cd "$ROOT_DIR"

START_TIME=$(date +%s%N)

MC_BIN="$(command -v mc || echo '/usr/bin/mc')"

# 1. Restore node_modules from the MinIO cache (read-only; the save job owns uploads)
NPM_CACHE_HIT=false
NPM_CACHE_KEY=""

restore_npm_cache() {
    if [ ! -x "$MC_BIN" ]; then
        echo "[CACHE OFFLINE] MinIO client ($MC_BIN) not executable. Running npm install."
        return 1
    fi
    if ! curl -s -m 2 "$MINIO_S3/minio/health/live" >/dev/null 2>&1; then
        echo "[CACHE OFFLINE] MinIO endpoint unreachable. Running npm install."
        return 1
    fi
    if ! $MC_BIN stat "$NPM_CACHE_TARGET" >/dev/null 2>&1; then
        echo "[CACHE MISS] No object at $NPM_CACHE_TARGET. Running npm install."
        return 1
    fi
    if ! $MC_BIN cp "$NPM_CACHE_TARGET" "$NODE_MODULES_ARCHIVE" >/dev/null; then
        echo "[CACHE MISS] Download of $NPM_CACHE_TARGET failed. Running npm install."
        return 1
    fi
    if ! $MC_BIN cp "${NPM_CACHE_TARGET}.sha256" "${NODE_MODULES_ARCHIVE}.sha256" >/dev/null 2>&1; then
        echo "[CACHE MISS] Integrity digest missing for $NPM_CACHE_TARGET. Running npm install."
        return 1
    fi
    EXPECTED_SHA="$(awk 'NR==1{print $1}' "${NODE_MODULES_ARCHIVE}.sha256")"
    ACTUAL_SHA="$(sha256sum "$NODE_MODULES_ARCHIVE" | awk '{print $1}')"
    if ! [[ "$EXPECTED_SHA" =~ ^[0-9a-f]{64}$ ]] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
        echo "[CACHE MISS] Digest mismatch (expected '$EXPECTED_SHA', actual '$ACTUAL_SHA'). Running npm install."
        return 1
    fi
    if ! tar -I "zstd -d -T0" -xf "$NODE_MODULES_ARCHIVE" -C "$ROOT_DIR"; then
        rm -rf "$ROOT_DIR/node_modules"
        echo "[CACHE MISS] Extraction failed. Running npm install."
        return 1
    fi
    echo "[CACHE HIT] Restored node_modules from $NPM_CACHE_TARGET."
}

if [ -d "node_modules" ]; then
    echo "[CACHE SKIP] node_modules already present; no restore attempted and no cache key reported."
else
    TMPROOT="${RUNNER_TEMP:-/tmp}"
    NODE_MODULES_ARCHIVE="$(mktemp -p "$TMPROOT" node_modules.XXXXXX.tar.zst)"
    trap 'rm -f "$NODE_MODULES_ARCHIVE" "${NODE_MODULES_ARCHIVE}.sha256"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    DEP_FILES=(package.json)
    if [ -f "package-lock.json" ]; then
        DEP_FILES+=(package-lock.json)
    fi
    NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
    DEPS_HASH="$(cat "${DEP_FILES[@]}" | sha256sum | awk '{print $1}')"
    NPM_CACHE_KEY="node${NODE_MAJOR}-${DEPS_HASH}/node_modules.tar.zst"
    NPM_CACHE_TARGET="${NPM_CACHE_ROOT}/${NPM_CACHE_KEY}"

    echo "==> node_modules missing. Checking remote cache ($NPM_CACHE_TARGET)..."
    if restore_npm_cache; then
        NPM_CACHE_HIT=true
    fi
    rm -f "$NODE_MODULES_ARCHIVE" "${NODE_MODULES_ARCHIVE}.sha256"
fi

{
    echo "npm_cache_hit=${NPM_CACHE_HIT}"
    echo "npm_cache_key=${NPM_CACHE_KEY}"
} >> "${GITHUB_OUTPUT:-/dev/null}"

if [ ! -d "node_modules" ]; then
    npm install --prefer-offline --no-audit --no-fund
fi

# 2. Execute Jest Tests
echo "==> Running Jest Unit Tests for Angular..."
npx jest --ci --colors --coverage

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo "=========================================================="
echo " [SUCCESS] Angular Jest Tests Completed in: ${DURATION_MS} ms"
echo "=========================================================="
