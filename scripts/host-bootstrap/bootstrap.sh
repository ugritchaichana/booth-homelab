#!/usr/bin/env bash
# ==============================================================================
# Master Orchestrator: Baremetal Host Proxmox VE 8.x Bootstrap Suite
# ==============================================================================
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

assert_root

LOG_FILE="/var/log/pve-bootstrap.log"
mkdir -p "$(dirname "${LOG_FILE}")"
exec > >(tee -a "${LOG_FILE}") 2>&1

STAGE="${1:---stage=1}"

echo -e "${BOLD}${CYAN}========================================================================${NC}"
echo -e "${BOLD}${CYAN}   Baremetal Homelab: Host Bootstrapping Engine                        ${NC}"
echo -e "${BOLD}${CYAN}   Target: Debian 12 -> Kernel 6.8+ -> PVE 8.x -> Routed NAT -> TS     ${NC}"
echo -e "${BOLD}${CYAN}========================================================================${NC}"
log_info "Bootstrap execution log: ${LOG_FILE}"

case "${STAGE}" in
    --stage=1|stage1)
        log_step "Executing Stage 1 (Pre-Reboot Baseline Installation)..."
        bash "${SCRIPT_DIR}/00-preflight-check.sh"
        bash "${SCRIPT_DIR}/01-setup-hosts-and-repos.sh"
        bash "${SCRIPT_DIR}/02-install-pve-kernel.sh"
        ;;

    --stage=2|stage2)
        log_step "Executing Stage 2 (Post-Reboot Proxmox Core & Network Provisioning)..."
        bash "${SCRIPT_DIR}/03-install-pve-core.sh"
        bash "${SCRIPT_DIR}/04-configure-routed-network.sh"
        bash "${SCRIPT_DIR}/05-apply-hardware-stability.sh"
        bash "${SCRIPT_DIR}/06-install-tailscale.sh"
        ;;

    --step=*)
        STEP_NUM="${STAGE#--step=}"
        TARGET_SCRIPT=$(find "${SCRIPT_DIR}" -name "${STEP_NUM}-*.sh" | head -n 1)
        if [[ -z "${TARGET_SCRIPT}" || ! -f "${TARGET_SCRIPT}" ]]; then
            log_error "No script matching step '${STEP_NUM}' found in ${SCRIPT_DIR}"
            exit 1
        fi
        log_step "Executing Single Step: $(basename "${TARGET_SCRIPT}")..."
        bash "${TARGET_SCRIPT}"
        ;;

    *)
        echo "Usage: sudo $0 [--stage=1 | --stage=2 | --step=00..06]"
        echo "  --stage=1   Run Pre-reboot steps (Pre-flight, Repos, PVE Kernel 6.8+)"
        echo "  --stage=2   Run Post-reboot steps (PVE Core, Routed NAT, Lid stability, Tailscale)"
        echo "  --step=XX   Run a specific numbered script (e.g. --step=04)"
        exit 1
        ;;
esac
