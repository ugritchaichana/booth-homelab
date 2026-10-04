#!/usr/bin/env bash
# ==============================================================================
# Step 05: Apply Clamshell, Wi-Fi Power, and Kernel Forwarding Overrides
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 05: Applying Hardware Stability & Uptime Overrides..."

# 1. Prevent Laptop Suspension on Lid Close
log_info "Configuring systemd-logind to ignore lid close events..."
mkdir -p /etc/systemd/logind.conf.d/
cat <<EOF > /etc/systemd/logind.conf.d/pve-laptop.conf
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF
systemctl restart systemd-logind
log_success "Lid close suspension override applied."

# 2. Disable Wi-Fi Power Save (Prevents WireGuard/SSH Disconnections)
WIFI_IFACE=$(detect_wifi_interface)
if [[ -n "${WIFI_IFACE}" ]]; then
    log_info "Disabling Wi-Fi power save for interface: ${WIFI_IFACE}..."
    if command -v iw &>/dev/null; then
        iw dev "${WIFI_IFACE}" set power_save off 2>/dev/null || true
    fi

    # Create persistent systemd service
    cat <<EOF > /etc/systemd/system/wifi-powersave-off.service
[Unit]
Description=Disable Wi-Fi Power Management for Homelab Uptime
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/iw dev ${WIFI_IFACE} set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable wifi-powersave-off.service 2>/dev/null || true
    log_success "Wi-Fi power-save kill switch service activated."
fi

# 3. Kernel IP Forwarding sysctl
log_info "Writing permanent IP Forwarding sysctl rules..."
cat <<EOF > /etc/sysctl.d/99-homelab.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
sysctl -p /etc/sysctl.d/99-homelab.conf
log_success "Kernel IP Forwarding permanently enabled."

log_success "Step 05 Completed: Hardware & Kernel Stability Overrides Active!"
exit 0
