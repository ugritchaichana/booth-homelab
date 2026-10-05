#!/usr/bin/env bash
# ==============================================================================
# Step 00: Pre-Flight Hardware & Network Sanity Verification
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root
log_step "Step 00: Executing Pre-Flight Hardware Sanity Checks..."

# 1. Architecture Validation
ARCH=$(uname -m)
log_info "System Architecture: ${ARCH}"
if [[ "${ARCH}" != "x86_64" ]]; then
    log_error "Unsupported architecture: ${ARCH}. Proxmox VE 8.x requires x86_64."
    exit 1
fi
log_success "Architecture is x86_64."

# 2. CPU Model & Thread Count
CPU_MODEL=$(grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs || true)
CPU_THREADS=$(nproc)
log_info "CPU Model:   ${CPU_MODEL}"
log_info "CPU Threads: ${CPU_THREADS}"
if [[ "${CPU_THREADS}" -lt 12 ]]; then
    log_warn "Host has fewer than 12 logical cores (${CPU_THREADS}). Meteor Lake 125H expects 18 threads."
else
    log_success "Meteor Lake multi-thread topology verified (${CPU_THREADS} threads)."
fi

# 3. RAM Budget Check
TOTAL_MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_GB=$(( TOTAL_MEM_KB / 1024 / 1024 ))
log_info "Physical Memory: ~${TOTAL_MEM_GB} GB"
if [[ "${TOTAL_MEM_GB}" -lt 14 ]]; then
    log_warn "Available RAM (${TOTAL_MEM_GB} GB) is less than the 16 GB baseline. Resource budget will be tight."
fi
if [[ "${TOTAL_MEM_GB}" -lt 8 ]]; then
    log_error "Available RAM is under 8 GB. Halting: Proxmox + SDET LXC stack will trigger OOM."
    exit 1
fi
log_success "Memory capacity is within workable boundaries (${TOTAL_MEM_GB} GB)."

# 4. Storage & Filesystem Check (ZFS Banned Check)
ROOT_FSTYPE=$(df -T / | awk 'NR==2 {print $2}')
log_info "Root Filesystem Type: ${ROOT_FSTYPE}"
if [[ "${ROOT_FSTYPE}" == "zfs" ]]; then
    log_error "CRITICAL: Root filesystem is ZFS! ZFS ARC will consume 50% of your 16GB RAM."
    log_error "Please reinstall Debian 12 with Ext4 on LVM-Thin to preserve memory for containers."
    exit 1
fi
log_success "Storage is non-ZFS (${ROOT_FSTYPE}). 100% RAM preserved for containers."

# 5. Wi-Fi Interface & Network Connectivity
WIFI_IFACE=$(detect_wifi_interface)
if [[ -z "${WIFI_IFACE}" ]]; then
    log_error "Could not detect a valid Wi-Fi interface (e.g. wlo1, wlan0). Is Wi-Fi hardware enabled?"
    exit 1
fi
log_success "Detected active Wi-Fi interface: ${WIFI_IFACE}"

log_info "Testing DNS and Internet Connectivity..."
if ! ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    log_error "Cannot reach public IP 1.1.1.1. Ensure host is connected to Wi-Fi/Ethernet."
    exit 1
fi
if ! ping -c 2 -W 3 debian.org &>/dev/null; then
    log_error "DNS resolution failed for debian.org. Check network captive portal authentication or DNS settings."
    exit 1
fi
log_success "Internet connectivity and DNS resolution verified."

log_success "Step 00 Pre-Flight Check Passed Successfully!"
exit 0
