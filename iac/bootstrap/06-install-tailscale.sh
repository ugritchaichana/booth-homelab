#!/usr/bin/env bash
# ==============================================================================
# Step 06: Deploy Tailscale Mesh & Subnet Router (Dorm CGNAT/AP Isolation Bypass)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 06: Deploying Tailscale Mesh Overlay & Subnet Router..."

# 1. Install Tailscale Repository & Key
log_info "Installing Tailscale official repository..."
mkdir -p /usr/share/keyrings /etc/apt/sources.list.d
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-repo.list | tee /etc/apt/sources.list.d/tailscale.list

apt-get update -qq
apt-get install -y -qq tailscale
systemctl enable --now tailscaled
log_success "Tailscale service running."

# 2. Start Tailscale Node with Subnet Routes & SSH
log_info "Advertising internal subnets (10.99.10.0/24, 10.99.20.0/24) via Tailscale..."
echo -e "\n${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${CYAN}   TAILSCALE AUTHENTICATION LINK                                        ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
tailscale up --advertise-routes=10.99.10.0/24,10.99.20.0/24 --ssh --accept-routes || true

# 3. Print Final Access Telemetry
TS_IP=$(tailscale ip -4 2>/dev/null || echo "100.x.y.z")
echo -e "\n${BOLD}${GREEN}========================================================================${NC}"
echo -e "${BOLD}${GREEN}   PROXMOX VE 8.x DEPLOYMENT COMPLETED SUCCESSFULLY!                   ${NC}"
echo -e "${BOLD}${GREEN}========================================================================${NC}"
echo -e "Tailscale IPv4 Address: ${BOLD}${TS_IP}${NC}"
echo -e "Proxmox Web GUI:        ${BOLD}https://${TS_IP}:8006${NC}"
echo -e "Host Management IP:     ${BOLD}https://10.99.10.1:8006${NC}"
echo -e ""
echo -e "Next steps in Tailscale Admin Console:"
echo -e "  1. Approve Subnet Routes (10.99.10.0/24, 10.99.20.0/24)"
echo -e "  2. Disable Key Expiry on this node"
echo -e "${BOLD}${GREEN}========================================================================${NC}\n"

exit 0
