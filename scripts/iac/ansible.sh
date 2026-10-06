#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
conf="${HOMELAB_CONFIG_DIR:-$HOME/.config/homelab}"

[ "$#" -gt 0 ] || { echo "usage: ansible.sh <playbook.yml|ad-hoc args> [args]" >&2; exit 2; }

[ -f "$conf/ssh_config" ] || "$repo/scripts/iac/render-ssh-config.sh"

export ANSIBLE_INVENTORY="$repo/iac/inventory/hosts.yml"
export ANSIBLE_HOST_KEY_CHECKING=True
export ANSIBLE_SSH_ARGS="-C -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes -F $conf/ssh_config"
unset ANSIBLE_SSH_COMMON_ARGS ANSIBLE_SSH_EXTRA_ARGS
[ ! -f "$repo/iac/ansible/ansible.cfg" ] || export ANSIBLE_CONFIG="$repo/iac/ansible/ansible.cfg"

case "$1" in
  *.yml|*.yaml)
    play="$1"; shift
    [ -f "$play" ] || play="$repo/iac/ansible/playbooks/$play"
    exec ansible-playbook "$play" "$@" ;;
  *) exec ansible "$@" ;;
esac
