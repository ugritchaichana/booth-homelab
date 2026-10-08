#!/usr/bin/env bash
set -euo pipefail

instance="${1:?usage: runner-restart.sh INSTANCE}"
[[ "$instance" =~ ^[0-9]+$ ]] || { echo "runner-restart: instance must be a number" >&2; exit 2; }
root="${RUNNER_ROOT:-/opt/actions-runner}-$instance"

for _ in $(seq 1 300); do
  pgrep -f "$root/bin/Runner.Worker" >/dev/null || break
  sleep 1
done
rm -f "/run/actions-runner-$instance/restart"
systemctl restart "actions-runner@$instance.service"
echo "runner-restart: restarted instance $instance"
