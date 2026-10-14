#!/usr/bin/env bash
set -euo pipefail

instance="${1:?usage: runner-restart.sh INSTANCE}"
[[ "$instance" =~ ^[0-9]+$ ]] || { echo "runner-restart: instance must be a number" >&2; exit 2; }
unit="actions-runner@$instance.service"
control_group="$(systemctl show -p ControlGroup --value "$unit")"

# All instances share one bound path: match the worker by cgroup.
worker_running() {
  [ -n "$control_group" ] || return 1
  local pid
  while read -r pid; do
    tr '\0' ' ' < "${PROC_ROOT:-/proc}/$pid/cmdline" 2>/dev/null | grep -q 'Runner\.Worker' && return 0
  done < "${CGROUP_ROOT:-/sys/fs/cgroup}$control_group/cgroup.procs"
  return 1
}

for _ in $(seq 1 "${RESTART_WAIT_SECONDS:-300}"); do
  worker_running || break
  sleep 1
done
rm -f "${RUN_ROOT:-/run}/actions-runner-$instance/restart"
systemctl restart "$unit"
echo "runner-restart: restarted instance $instance"
