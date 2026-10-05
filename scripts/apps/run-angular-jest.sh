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

# 1. Restore node_modules from MinIO cache if available
if [ ! -d "node_modules" ]; then
    TMPROOT="${RUNNER_TEMP:-/tmp}"
    NODE_MODULES_ARCHIVE="$(mktemp -p "$TMPROOT" node_modules.XXXXXX.tar.zst)"
    trap 'rm -f "$NODE_MODULES_ARCHIVE"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    DEP_FILES=(package.json)
    if [ -f "package-lock.json" ]; then
        DEP_FILES+=(package-lock.json)
    fi
    NODE_MAJOR="$(node -p "process.versions.node.split('.')[0]")"
    DEPS_HASH="$(cat "${DEP_FILES[@]}" | sha256sum | awk '{print $1}')"
    NPM_CACHE_TARGET="${NPM_CACHE_ROOT}/node${NODE_MAJOR}-${DEPS_HASH}/node_modules.tar.zst"

    case "${GITHUB_EVENT_NAME:-}:${GITHUB_REF:-}" in
        push:refs/heads/master|push:refs/heads/main) CACHE_WRITE_ALLOWED=true ;;
        *) CACHE_WRITE_ALLOWED=false ;;
    esac

    echo "==> node_modules missing. Checking remote cache ($NPM_CACHE_TARGET)..."
    NPM_RESTORED=false
    if [ -x "$MC_BIN" ] && curl -s -m 2 "$MINIO_S3/minio/health/live" >/dev/null 2>&1 && $MC_BIN stat "$NPM_CACHE_TARGET" >/dev/null 2>&1; then
        echo "[CACHE HIT] Found node_modules cache on MinIO. Downloading..."
        if $MC_BIN cp "$NPM_CACHE_TARGET" "$NODE_MODULES_ARCHIVE" && tar -I "zstd -d -T0" -xf "$NODE_MODULES_ARCHIVE" -C "$ROOT_DIR"; then
            NPM_RESTORED=true
            echo "[OK] Restored node_modules from MinIO virtual bus."
        else
            echo "[WARN] Cache download or extraction failed. Falling back to npm install."
            rm -rf "$ROOT_DIR/node_modules"
        fi
        rm -f "$NODE_MODULES_ARCHIVE"
    fi

    if [ "$NPM_RESTORED" != "true" ]; then
        echo "[CACHE MISS / S3 OFFLINE] Running npm install..."
        npm install --prefer-offline --no-audit --no-fund
        if [ "$CACHE_WRITE_ALLOWED" != "true" ]; then
            echo "[SKIP] Not a push to master/main. node_modules cache upload disabled."
        elif [ -x "$MC_BIN" ] && curl -s -m 2 "$MINIO_S3/minio/health/live" >/dev/null 2>&1; then
            echo "==> Archiving node_modules to MinIO..."
            if tar -I "zstd -T0 -3" -cf "$NODE_MODULES_ARCHIVE" node_modules 2>/dev/null; then
                $MC_BIN cp "$NODE_MODULES_ARCHIVE" "$NPM_CACHE_TARGET" 2>/dev/null || true
            fi
            rm -f "$NODE_MODULES_ARCHIVE"
        fi
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
