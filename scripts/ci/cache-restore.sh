#!/usr/bin/env bash
# ==============================================================================
# Ultra-Optimized Deep Cache Restore for .NET CI/CD (Proxmox S3 / MinIO)
# ==============================================================================
set -euo pipefail

BRANCH_NAME="${1:-master}"
SAFE_BRANCH=$(echo "$BRANCH_NAME" | sed 's#[^a-zA-Z0-9._-]#_#g')
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPROOT="${RUNNER_TEMP:-/tmp}"
TARGET_FILE="$(mktemp -p "$TMPROOT" cache-restore.XXXXXX.tar.zst)"
trap 'rm -f "$TARGET_FILE" "${TARGET_FILE}.sha256"' EXIT INT TERM

echo "=========================================================="
echo "      ENTERPRISE DEEP CACHE RESTORE (MINIO S3)           "
echo "=========================================================="
echo "Branch:     $SAFE_BRANCH"
echo "Workspace:  $ROOT_DIR"
echo "S3 Server:  http://10.99.20.20:9000 (Local Virtual Bus)"

MC_BIN="$(command -v mc || echo '/usr/bin/mc')"

# Graceful Degradation Check 1: MinIO CLI Availability
if [ ! -x "$MC_BIN" ]; then
    echo "[WARN] MinIO client ($MC_BIN) not executable. Proceeding with clean build without cache."
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

# Graceful Degradation Check 2: Endpoint Health Probing (2s timeout)
if ! curl -s -m 2 http://10.99.20.20:9000/minio/health/live >/dev/null 2>&1; then
    echo "[WARN] MinIO S3 endpoint unreachable. Gracefully falling back to fresh build."
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

CANDIDATES=(
    "minio/build-cache/branches/${SAFE_BRANCH}/latest.tar.zst"
    "minio/build-cache/branches/master/latest.tar.zst"
    "minio/build-cache/branches/main/latest.tar.zst"
    "minio/build-cache/global/latest.tar.zst"
)

FOUND_TARGET=""
for candidate in "${CANDIDATES[@]}"; do
    if $MC_BIN stat "$candidate" >/dev/null 2>&1; then
        FOUND_TARGET="$candidate"
        break
    fi
done

if [ -z "$FOUND_TARGET" ]; then
    echo "[CACHE MISS] No compatible cache found on S3. Full clean build required."
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

echo "[CACHE HIT] Found S3 Cache Target: $FOUND_TARGET"
SIZE=$($MC_BIN stat --json "$FOUND_TARGET" | jq -r '.size // 0')
echo "Payload Size: $((SIZE / 1024 / 1024)) MB ($SIZE bytes)"

START_TIME=$(date +%s%N)
if ! $MC_BIN cp "$FOUND_TARGET" "$TARGET_FILE" 2>/dev/null; then
    echo "[WARN] Download interrupted or timed out. Proceeding with clean build."
    rm -f "$TARGET_FILE"
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

DL_END=$(date +%s%N)
DL_MS=$(( (DL_END - START_TIME) / 1000000 ))
echo "[PASS] Downloaded in ${DL_MS} ms from local virtual bus."

# Download SHA256 integrity digest
if ! $MC_BIN cp "${FOUND_TARGET}.sha256" "${TARGET_FILE}.sha256" 2>/dev/null; then
    echo "[WARN] Integrity digest missing for cache target ($FOUND_TARGET). Rejecting untrusted cache."
    rm -f "$TARGET_FILE"
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

# Verify SHA256 checksum
EXPECTED_SHA=$(awk '{print $1}' "${TARGET_FILE}.sha256")
ACTUAL_SHA=$(sha256sum "$TARGET_FILE" | awk '{print $1}')
if [ -z "$EXPECTED_SHA" ] || [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    echo "[ABORT] Cache integrity verification failed! Expected: '$EXPECTED_SHA', Actual: '$ACTUAL_SHA'"
    rm -f "$TARGET_FILE" "${TARGET_FILE}.sha256"
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 1
fi
echo "[PASS] Verified SHA256 integrity digest ($ACTUAL_SHA)."

# Decompress strictly to ROOT_DIR with zstd multi-threaded (GNU tar strips leading / by default)
echo "==> Decompressing cache payload via zstd into workspace..."
if ! tar -I "zstd -d -T0" -xf "$TARGET_FILE" -C "$ROOT_DIR" 2>/dev/null; then
    echo "[WARN] Corrupted or invalid cache payload. Discarding cache and continuing clean build."
    rm -f "$TARGET_FILE" "${TARGET_FILE}.sha256"
    echo "CACHE_HIT=false" >> "${GITHUB_ENV:-/dev/null}"
    exit 0
fi

EXTRACT_END=$(date +%s%N)
EXTRACT_MS=$(( (EXTRACT_END - DL_END) / 1000000 ))
echo "[PASS] Decompressed in ${EXTRACT_MS} ms."
rm -f "$TARGET_FILE" "${TARGET_FILE}.sha256"

# Link restored NuGet cache to HOME if needed for external tool resolution
if [ -d "$ROOT_DIR/.nuget/packages" ] && [ ! -d "$HOME/.nuget/packages" ]; then
    mkdir -p "$HOME/.nuget"
    ln -s "$ROOT_DIR/.nuget/packages" "$HOME/.nuget/packages" 2>/dev/null || true
fi

# MSBuild Timestamp Synchronization:
# Touch all restored dlls and obj inputs to current time so MSBuild sees them as fresh
echo "==> Synchronizing MSBuild Intermediate Timestamps..."
NOW_SEC=$(date +%s)
find "$ROOT_DIR/apps/backend" -type d \( -name "bin" -o -name "obj" \) -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true
find "$ROOT_DIR/apps/backend" -type f \( -name "*.dll" -o -name "*.cache" -o -name "project.assets.json" \) -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true

# Any files modified in git diff against base commit should have timestamps strictly AFTER the output DLLs
# to trigger surgical recompilation for ONLY modified projects
if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    BASE_REF="HEAD~1"
else
    BASE_REF="origin/master"
fi

CHANGED_SOURCES=$(git diff --name-only "$BASE_REF" HEAD 2>/dev/null || true)
if [ -n "$CHANGED_SOURCES" ]; then
    FUTURE_SEC=$((NOW_SEC + 5))
    echo "==> Bumping timestamps for $(echo "$CHANGED_SOURCES" | wc -l) modified source files to trigger surgical build..."
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            touch -d "@$FUTURE_SEC" "$f"
            echo "    - Bumped: $f"
        fi
    done <<< "$CHANGED_SOURCES"
fi

NOW_END=$(date +%s%N)
TOTAL_RESTORE_MS=$(( (NOW_END - START_TIME) / 1000000 ))
echo "=========================================================="
echo " [OK] Total Cache Restore Time: ${TOTAL_RESTORE_MS} ms"
echo "=========================================================="
echo "CACHE_HIT=true" >> "${GITHUB_ENV:-/dev/null}"
