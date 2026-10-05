#!/usr/bin/env bash
# ==============================================================================
# Ultra-Optimized Deep Cache Save for .NET CI/CD (Proxmox S3 / MinIO)
# ==============================================================================
set -euo pipefail

BRANCH_NAME="${1:-master}"
CACHE_KEY="${2:-$(git rev-parse --short HEAD)}"
SAFE_BRANCH=$(echo "$BRANCH_NAME" | sed 's#[^a-zA-Z0-9._-]#_#g')
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_ARCHIVE="/tmp/cache-payload.tar.zst"

echo "=========================================================="
echo "        ENTERPRISE DEEP CACHE SAVE (MINIO S3)            "
echo "=========================================================="
echo "Branch:     $SAFE_BRANCH"
echo "Cache Key:  $CACHE_KEY"
echo "Workspace:  $ROOT_DIR"

START_TIME=$(date +%s%N)

MC_BIN="$(command -v mc || echo '/usr/bin/mc')"

# Graceful Degradation: Skip save if mc or MinIO is unavailable
if [ ! -x "$MC_BIN" ]; then
    echo "[WARN] MinIO client ($MC_BIN) not executable. Skipping cache save."
    exit 0
fi

if ! curl -s -m 2 http://10.99.20.20:9000/minio/health/live >/dev/null 2>&1; then
    echo "[WARN] MinIO S3 endpoint unreachable. Skipping cache save."
    exit 0
fi

# 1. Collect Cache Targets: NuGet Packages + Bin + Obj
CACHE_PATHS=()
if [ -d "$HOME/.nuget/packages" ]; then
    CACHE_PATHS+=("$HOME/.nuget/packages")
fi

while IFS= read -r dir; do
    [ -d "$dir" ] && CACHE_PATHS+=("$dir")
done < <(find "$ROOT_DIR/apps/backend" -type d \( -name "bin" -o -name "obj" \))

echo "==> Packing ${#CACHE_PATHS[@]} targets into zstd compressed stream..."

# Tar + zstd -T0 -3 with mtime preservation
tar -I "zstd -T0 -3" -cf "$TARGET_ARCHIVE" "${CACHE_PATHS[@]}"

COMPRESS_END=$(date +%s%N)
COMPRESS_MS=$(( (COMPRESS_END - START_TIME) / 1000000 ))
RAW_SIZE=$(du -sh "$TARGET_ARCHIVE" | awk '{print $1}')
echo "[PASS] Compressed in ${COMPRESS_MS} ms (Payload Size: $RAW_SIZE)."

# 2. Upload to MinIO S3 over Virtual Bus
echo "==> Uploading to MinIO S3 over high-speed Proxmox Virtual Bus..."
$MC_BIN cp "$TARGET_ARCHIVE" "minio/build-cache/branches/${SAFE_BRANCH}/${CACHE_KEY}.tar.zst" || echo "[WARN] Branch cache upload skipped."
$MC_BIN cp "$TARGET_ARCHIVE" "minio/build-cache/branches/${SAFE_BRANCH}/latest.tar.zst" || echo "[WARN] Latest cache upload skipped."

if [ "$SAFE_BRANCH" == "master" ] || [ "$SAFE_BRANCH" == "main" ]; then
    echo "==> Updating global baseline cache..."
    $MC_BIN cp "$TARGET_ARCHIVE" "minio/build-cache/global/latest.tar.zst" || echo "[WARN] Global cache upload skipped."
fi

UPLOAD_END=$(date +%s%N)
UPLOAD_MS=$(( (UPLOAD_END - COMPRESS_END) / 1000000 ))
echo "[PASS] Uploaded in ${UPLOAD_MS} ms."

rm -f "$TARGET_ARCHIVE"

TOTAL_SAVE_MS=$(( (UPLOAD_END - START_TIME) / 1000000 ))
echo "=========================================================="
echo " [OK] Total Cache Save Time: ${TOTAL_SAVE_MS} ms"
echo "=========================================================="
