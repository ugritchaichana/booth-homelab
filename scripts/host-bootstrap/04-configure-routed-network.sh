#!/usr/bin/env bash
# ==============================================================================
# Step 04: Configure Routed Wi-Fi NAT Networking (/etc/network/interfaces)
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 04: Configuring Routed NAT Network Fabric & Bridges..."

WIFI_IFACE=$(detect_wifi_interface)
if [[ -z "${WIFI_IFACE}" ]]; then
    log_error "Could not detect active Wi-Fi interface. Ensure Wi-Fi is enabled."
    exit 1
fi
log_info "Binding Routed NAT to Wi-Fi Interface: ${WIFI_IFACE}"

INTERFACES_FILE="/etc/network/interfaces"
BACKUP_FILE="/etc/network/interfaces.bak.$(date +%s)"

log_info "Creating backup of current interfaces: ${BACKUP_FILE}"
cp "${INTERFACES_FILE}" "${BACKUP_FILE}"

# Write Routed NAT Configuration
cat <<EOF > "${INTERFACES_FILE}"
auto lo
iface lo inet loopback

# Primary Wi-Fi Interface
iface ${WIFI_IFACE} inet dhcp

# Proxmox Virtual Management Bridge (vmbr0)
auto vmbr0
iface vmbr0 inet static
    address 10.99.10.1/24
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    # Enable IP Forwarding and NAT masquerading through Wi-Fi
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s '10.99.10.0/24' -o ${WIFI_IFACE} -j MASQUERADE
    post-up iptables -t nat -A POSTROUTING -s '10.99.20.0/24' -o ${WIFI_IFACE} -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s '10.99.10.0/24' -o ${WIFI_IFACE} -j MASQUERADE
    post-down iptables -t nat -D POSTROUTING -s '10.99.20.0/24' -o ${WIFI_IFACE} -j MASQUERADE

# Isolated SDET / Test DMZ Virtual Bridge (vmbr1)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
EOF

log_success "Routed NAT configuration written to ${INTERFACES_FILE}"

# Apply networking safely
log_info "Applying network configuration..."
if command -v ifreload &>/dev/null; then
    ifreload -a || {
        log_error "Network reload failed! Rolling back to ${BACKUP_FILE}..."
        cp "${BACKUP_FILE}" "${INTERFACES_FILE}"
        ifreload -a || true
        exit 1
    }
else
    systemctl restart networking || {
        log_error "Networking restart failed! Rolling back..."
        cp "${BACKUP_FILE}" "${INTERFACES_FILE}"
        systemctl restart networking || true
        exit 1
    }
fi

log_success "Step 04 Completed: Routed NAT & Bridges (vmbr0, vmbr1) Active!"
exit 0
