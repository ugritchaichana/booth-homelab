#!/usr/bin/env bash
# ==============================================================================
# OpenTofu Homelab State Import Tooling (POSIX / Linux / macOS)
# ==============================================================================
# Imports live Proxmox LXC containers (CT 102, 103, 104) into OpenTofu state.
# ==============================================================================
set -euo pipefail

NODE_NAME="${1:-pve}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOFU_BIN="${TOFU_BIN:-$(command -v tofu || echo 'tofu')}"

echo "=========================================================="
echo "      OPENTOFU HOMELAB STATE IMPORT TOOLING               "
echo "=========================================================="
echo "Target Proxmox Node: $NODE_NAME"
echo "IaC Directory:       $SCRIPT_DIR"
echo "OpenTofu Binary:     $TOFU_BIN"
echo ""

declare -A TARGETS=(
    ["module.runner_dotnet.proxmox_virtual_environment_container.this"]="102"
    ["module.runner_angular.proxmox_virtual_environment_container.this"]="103"
    ["module.minio_cache.proxmox_virtual_environment_container.this"]="104"
)

for address in "${!TARGETS[@]}"; do
    vmid="${TARGETS[$address]}"
    import_id="${NODE_NAME}/${vmid}"
    echo "==> Importing CT ${vmid} -> ${address}..."
    "$TOFU_BIN" -chdir="$SCRIPT_DIR" import "$address" "$import_id" || echo "[WARN] Already imported or import skipped."
done

echo ""
echo "==> Verifying OpenTofu State Drift..."
"$TOFU_BIN" -chdir="$SCRIPT_DIR" plan
