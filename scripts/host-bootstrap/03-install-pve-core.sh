#!/usr/bin/env bash
# ==============================================================================
# Step 03: Install Proxmox VE 8.x Core Daemons, Postfix, & Sanitize GRUB
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 03: Installing Proxmox VE 8.x Core Stack & Sanitizing Host..."

# 1. Assert Booted Kernel is PVE Kernel
RUNNING_KERNEL=$(uname -r)
log_info "Active Running Kernel: ${RUNNING_KERNEL}"
if [[ "${RUNNING_KERNEL}" != *"-pve"* ]]; then
    log_error "Active kernel is not a Proxmox kernel (${RUNNING_KERNEL})."
    log_error "Please ensure you have rebooted and selected the Proxmox kernel in UEFI GRUB."
    exit 1
fi
log_success "Verified running under Proxmox Kernel (${RUNNING_KERNEL})."

# 2. Pre-seed Debconf for Non-Interactive Postfix
log_info "Pre-seeding debconf selections for unattended Postfix installation..."
CURRENT_HOST=$(hostname)
echo "postfix postfix/main_mailer_type select Local only" | debconf-set-selections
echo "postfix postfix/mailname string ${CURRENT_HOST}.local" | debconf-set-selections

# 3. Install Proxmox VE Core, Storage Daemons, and Chrony NTP
log_info "Installing proxmox-ve, postfix, open-iscsi, and chrony..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-ve postfix open-iscsi chrony

# 4. Remove Stock Debian Kernel to Prevent Upgrade Drift
log_info "Removing Debian stock 6.1 kernel..."
DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq linux-image-amd64 'linux-image-6.1*' 2>/dev/null || true

# 5. Remove os-prober (Proxmox Best Practice)
log_info "Removing os-prober to protect virtual disks from GRUB scanning..."
DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq os-prober 2>/dev/null || true

# 6. Update GRUB
log_info "Updating GRUB configuration..."
update-grub

log_success "Step 03 Completed: Proxmox VE 8.x Core Stack Installed & Sanitized."
exit 0
