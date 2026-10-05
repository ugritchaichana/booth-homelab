#!/usr/bin/env bash
# ==============================================================================
# Step 01: Setup /etc/hosts, PVE Repositories, SHA512 GPG Key, and Wi-Fi Firmware
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 01: Configuring Hostname Resolution, Repositories & GPG Keys..."

CURRENT_HOST=$(hostname)
MANAGEMENT_IP="10.99.10.1"
EXPECTED_PVE_GPG_SHA512="7da6fe34168adc6e479327ba517796d4702fa2f8b4f0a9833f5ea6e6b48f6507a6da403a274fe201595edc86a84463d50383d07f64bdde2e3658108db7d6dc87"

# 1. Fix /etc/hosts (Remove 127.0.1.1, ensure 10.99.10.1 mapping)
log_info "Sanitizing /etc/hosts for Proxmox cluster compatibility..."
cp /etc/hosts /etc/hosts.bak."$(date +%s)"

# Delete any existing 127.0.1.1 entries
sed -i "/127\.0\.1\.1/d" /etc/hosts

# Ensure localhost is present
if ! grep -q "127.0.0.1[[:space:]]\+localhost" /etc/hosts; then
    echo "127.0.0.1       localhost" >> /etc/hosts
fi

# Ensure 10.99.10.1 maps to hostname
if grep -q "${MANAGEMENT_IP}" /etc/hosts; then
    sed -i "s/${MANAGEMENT_IP}.*/${MANAGEMENT_IP}      ${CURRENT_HOST}.local ${CURRENT_HOST}/" /etc/hosts
else
    echo "${MANAGEMENT_IP}      ${CURRENT_HOST}.local ${CURRENT_HOST}" >> /etc/hosts
fi

log_success "/etc/hosts configured: ${MANAGEMENT_IP} -> ${CURRENT_HOST}.local ${CURRENT_HOST}"

# 2. Add Proxmox VE 8.x No-Subscription Repository
log_info "Configuring Proxmox VE 8.x repository..."
PVE_REPO_FILE="/etc/apt/sources.list.d/pve-install-repo.list"
echo "deb [arch=amd64] http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > "${PVE_REPO_FILE}"
log_success "PVE repository written to ${PVE_REPO_FILE}"

# 3. Download and Verify Proxmox Release GPG Key
log_info "Fetching Proxmox Release GPG Key..."
GPG_DEST="/etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg"
mkdir -p /etc/apt/trusted.gpg.d/
wget -q https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg -O "${GPG_DEST}"

log_info "Asserting cryptographic SHA512 integrity of GPG Key..."
ACTUAL_SHA512=$(sha512sum "${GPG_DEST}" | awk '{print $1}')
if [[ "${ACTUAL_SHA512}" != "${EXPECTED_PVE_GPG_SHA512}" ]]; then
    log_error "SECURITY ALERT: GPG Key SHA512 mismatch!"
    log_error "Expected: ${EXPECTED_PVE_GPG_SHA512}"
    log_error "Actual:   ${ACTUAL_SHA512}"
    rm -f "${GPG_DEST}"
    exit 1
fi
log_success "Proxmox GPG Key verified bit-for-bit against official upstream."

# 4. Update Package Cache and Install Intel Wi-Fi Firmware
log_info "Updating apt package index..."
apt-get update -qq

log_info "Installing Intel Wi-Fi 7 (firmware-iwlwifi) and essential tools..."
apt-get install -y -qq firmware-iwlwifi curl wget gnupg ca-certificates

log_success "Step 01 Completed Successfully!"
exit 0
