#!/usr/bin/env bash
# ==============================================================================
# Ultra-Optimized Deep Cache Save for .NET CI/CD (Proxmox S3 / MinIO)
# ==============================================================================
set -euo pipefail

BRANCH_NAME="${1:-master}"
CACHE_KEY="${2:-$(git rev-parse --short HEAD)}"
SAFE_BRANCH=$(echo "$BRANCH_NAME" | sed 's#[^a-zA-Z0-9._-]#_#g')
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMPROOT="${RUNNER_TEMP:-/tmp}"
TARGET_ARCHIVE="$(mktemp -p "$TMPROOT" cache-payload.XXXXXX.tar.zst)"
TARGET_SHA="${TARGET_ARCHIVE}.sha256"
trap 'rm -f "$TARGET_ARCHIVE" "$TARGET_SHA"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

# 1. Collect Cache Targets strictly relative to ROOT_DIR
cd "$ROOT_DIR"
CACHE_PATHS=()

# Stage NuGet packages into workspace if located in HOME
if [ -d ".nuget/packages" ]; then
    CACHE_PATHS+=(".nuget/packages")
elif [ -d "$HOME/.nuget/packages" ]; then
    mkdir -p "$ROOT_DIR/.nuget"
    cp -al "$HOME/.nuget/packages" "$ROOT_DIR/.nuget/" 2>/dev/null || cp -r "$HOME/.nuget/packages" "$ROOT_DIR/.nuget/" 2>/dev/null || true
    [ -d ".nuget/packages" ] && CACHE_PATHS+=(".nuget/packages")
fi

while IFS= read -r dir; do
    [ -d "$dir" ] && CACHE_PATHS+=("${dir#./}")
done < <(find apps/backend -type d \( -name "bin" -o -name "obj" \))

if [ ${#CACHE_PATHS[@]} -eq 0 ]; then
    echo "[WARN] No cache paths found to save."
    exit 0
fi

echo "==> Packing ${#CACHE_PATHS[@]} targets into workspace-relative zstd compressed stream..."

# Tar relative to ROOT_DIR + zstd -T0 -3 with mtime preservation
tar -I "zstd -T0 -3" -cf "$TARGET_ARCHIVE" "${CACHE_PATHS[@]}"

COMPRESS_END=$(date +%s%N)
COMPRESS_MS=$(( (COMPRESS_END - START_TIME) / 1000000 ))
RAW_SIZE=$(du -sh "$TARGET_ARCHIVE" | awk '{print $1}')
echo "[PASS] Compressed in ${COMPRESS_MS} ms (Payload Size: $RAW_SIZE)."

# 2. Compute writer SHA256 integrity checksum
echo "==> Generating SHA256 integrity digest..."
ARCHIVE_SHA=$(sha256sum "$TARGET_ARCHIVE" | awk '{print $1}')
echo "[PASS] Checksum: $ARCHIVE_SHA"

# 3. Upload archive and digest to MinIO S3 over Virtual Bus
echo "==> Uploading to MinIO S3 over high-speed Proxmox Virtual Bus..."
if $MC_BIN alias list minio-writer >/dev/null 2>&1; then
    S3_ALIAS="minio-writer"
else
    S3_ALIAS="minio"
fi

upload_with_digest() {
    local object="$1"
    printf '%s  %s\n' "$ARCHIVE_SHA" "$(basename "$object")" > "$TARGET_SHA"
    $MC_BIN cp "$TARGET_ARCHIVE" "$object" || echo "[WARN] Cache upload skipped: $object"
    $MC_BIN cp "$TARGET_SHA" "${object}.sha256" || echo "[WARN] Digest upload skipped: $object"
}

upload_with_digest "${S3_ALIAS}/build-cache/branches/${SAFE_BRANCH}/${CACHE_KEY}.tar.zst"
upload_with_digest "${S3_ALIAS}/build-cache/branches/${SAFE_BRANCH}/latest.tar.zst"

if [ "$SAFE_BRANCH" == "master" ] || [ "$SAFE_BRANCH" == "main" ]; then
    echo "==> Updating global baseline cache..."
    upload_with_digest "${S3_ALIAS}/build-cache/global/latest.tar.zst"
fi

UPLOAD_END=$(date +%s%N)
UPLOAD_MS=$(( (UPLOAD_END - COMPRESS_END) / 1000000 ))
echo "[PASS] Uploaded in ${UPLOAD_MS} ms."

rm -f "$TARGET_ARCHIVE" "$TARGET_SHA"

TOTAL_SAVE_MS=$(( (UPLOAD_END - START_TIME) / 1000000 ))
echo "=========================================================="
echo " [OK] Total Cache Save Time: ${TOTAL_SAVE_MS} ms"
echo "=========================================================="
