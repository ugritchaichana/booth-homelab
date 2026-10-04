#!/usr/bin/env bash
# ==============================================================================
# Step 02: Install Proxmox Default Kernel (Kernel 6.8+) for Meteor Lake
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 02: Installing Proxmox Default Kernel (6.8+ Enterprise Stack)..."

log_info "Running apt full-upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq

log_info "Installing proxmox-default-kernel..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-default-kernel

# Verify kernel package is installed
if ! dpkg -l | grep -q "proxmox-default-kernel"; then
    log_error "Package proxmox-default-kernel failed to install."
    exit 1
fi

log_success "proxmox-default-kernel installed successfully."
log_info "Updating GRUB bootloader..."
update-grub

# Create stage checkpoint
mkdir -p /var/lib/pve-bootstrap
touch /var/lib/pve-bootstrap/kernel-installed

echo -e "\n${BOLD}${YELLOW}========================================================================${NC}"
echo -e "${BOLD}${YELLOW}   [CHECKPOINT REQUIRED] MANDATORY SYSTEM REBOOT                       ${NC}"
echo -e "${BOLD}${YELLOW}========================================================================${NC}"
echo -e "You have successfully installed the Proxmox 6.8+ Kernel."
echo -e "You MUST reboot the host now to boot into the new kernel before installing"
echo -e "the Proxmox VE userland packages."
echo -e ""
echo -e "Command to reboot: ${BOLD}sudo reboot${NC}"
echo -e "After reboot, re-run: ${BOLD}sudo ./bootstrap.sh --stage=2${NC}"
echo -e "${BOLD}${YELLOW}========================================================================${NC}\n"

exit 0
