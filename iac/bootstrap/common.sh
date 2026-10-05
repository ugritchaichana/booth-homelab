#!/usr/bin/env bash
# ==============================================================================
# Homelab SDET Rig: Common Utilities & Safety Assertions
# ==============================================================================
set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Central Logging Functions
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$*${NC}"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Fatal Error Handler Trap
error_handler() {
    local exit_code="$1"
    local line_num="$2"
    local command="$3"
    log_error "Command failed with exit code ${exit_code} at line ${line_num}: '${command}'"
    exit "${exit_code}"
}
trap 'error_handler $? $LINENO "$BASH_COMMAND"' ERR

# Safety Assertions
assert_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be executed as root. (Run: sudo $0)"
        exit 1
    fi
}

assert_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" &>/dev/null; then
        log_error "Required command '${cmd}' is missing. Install prerequisites before continuing."
        exit 1
    fi
}

assert_file() {
    local path="$1"
    if [[ ! -f "${path}" ]]; then
        log_error "Expected file '${path}' does not exist."
        exit 1
    fi
}

# Auto-detect Primary Wi-Fi Interface
detect_wifi_interface() {
    local iface=""
    if command -v iw &>/dev/null; then
        iface=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | head -n 1 || true)
    fi
    if [[ -z "${iface}" ]]; then
        iface=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^wl' | head -n 1 || true)
    fi
    echo "${iface}"
}
