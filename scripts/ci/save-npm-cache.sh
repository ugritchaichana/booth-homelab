#!/usr/bin/env bash
# Usage: save-npm-cache.sh <cache-key>   (key relative to minio-writer/build-cache/npm/)
# Requires the minio-writer alias in MC_CONFIG_DIR.
set -euo pipefail

CACHE_KEY="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/apps/frontend"
CACHE_OBJECT="minio-writer/build-cache/npm/${CACHE_KEY}"

if [ -z "$CACHE_KEY" ]; then
    echo "::warning::No npm cache key from the test job; skipping npm cache save."
    exit 0
fi

if [ ! -d "$FRONTEND_DIR/node_modules" ]; then
    echo "::warning::$FRONTEND_DIR/node_modules not found (ephemeral or different runner); skipping npm cache save."
    exit 0
fi

WORK_DIR="$(mktemp -d -p "${RUNNER_TEMP:-/tmp}" npm-cache-save.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ARCHIVE="$WORK_DIR/$(basename "$CACHE_KEY")"
DIGEST="${ARCHIVE}.sha256"

echo "==> Archiving apps/frontend/node_modules for $CACHE_KEY"
tar -I "zstd -T0 -3" -C "$FRONTEND_DIR" -cf "$ARCHIVE" node_modules
ARCHIVE_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"
printf '%s  %s\n' "$ARCHIVE_SHA" "$(basename "$ARCHIVE")" > "$DIGEST"

echo "==> Uploading digest, then archive ($(du -h "$ARCHIVE" | awk '{print $1}'))"
mc cp "$DIGEST" "${CACHE_OBJECT}.sha256" >/dev/null
mc cp "$ARCHIVE" "$CACHE_OBJECT" >/dev/null
echo "[PASS] Saved npm cache $CACHE_KEY (sha256 $ARCHIVE_SHA)."
