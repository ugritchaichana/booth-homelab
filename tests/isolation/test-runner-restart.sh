#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${RUNNER_RESTART_SCRIPT:-$repo/scripts/ci/runner-restart.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
[ -f "$script" ] || { echo "ERROR: no script at $script" >&2; exit 2; }

mkdir -p "$work/bin"
cat > "$work/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "systemctl $*" >> "$CALLS"
[ "$1" = show ] && printf '%s\n' "$FAKE_CONTROL_GROUP"
exit 0
STUB
cat > "$work/bin/sleep" <<'STUB'
#!/usr/bin/env bash
echo "sleep $*" >> "$CALLS"
STUB
chmod +x "$work/bin/systemctl" "$work/bin/sleep"

process() {
  mkdir -p "$work/proc/$1" "$work/cgroup$2"
  printf '%s\0' "${@:3}" > "$work/proc/$1/cmdline"
  echo "$1" >> "$work/cgroup$2/cgroup.procs"
}

fails=0
run() {
  local name=$1 want_sleeps=$2 control_group=$3 rc=0
  : > "$work/calls"
  mkdir -p "$work/run/actions-runner-1" && touch "$work/run/actions-runner-1/restart"
  env PATH="$work/bin:$PATH" CALLS="$work/calls" FAKE_CONTROL_GROUP="$control_group" PROC_ROOT="$work/proc" CGROUP_ROOT="$work/cgroup" \
    RUN_ROOT="$work/run" RESTART_WAIT_SECONDS=3 bash "$script" 1 > "$work/out" 2>&1 || rc=$?
  local sleeps restarts
  sleeps=$(grep -c '^sleep' "$work/calls" || true)
  restarts=$(grep -c '^systemctl restart actions-runner@1.service$' "$work/calls" || true)
  if [ "$rc" -eq 0 ] && [ "$sleeps" -eq "$want_sleeps" ] && [ "$restarts" -eq 1 ] && [ ! -e "$work/run/actions-runner-1/restart" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name: rc=$rc sleeps=$sleeps restarts=$restarts $(cat "$work/out")"
    fails=$((fails + 1))
  fi
}

process 11 /system.slice/actions-runner@1.service /opt/actions-runner/bin/Runner.Listener run
process 21 /system.slice/actions-runner@2.service /opt/actions-runner/bin/Runner.Worker spawnclient 1 2
run "a worker of another instance with the same path does not delay the restart" 0 /system.slice/actions-runner@1.service
run "an instance that is not running restarts at once" 0 ""

process 12 /system.slice/actions-runner@1.service /opt/actions-runner/bin/Runner.Worker spawnclient 3 4
run "a worker in this instance's cgroup delays the restart until the wait ends" 3 /system.slice/actions-runner@1.service

rc=0
env PATH="$work/bin:$PATH" CALLS="$work/calls" FAKE_CONTROL_GROUP="" bash "$script" one > "$work/out" 2>&1 || rc=$?
if [ "$rc" -eq 2 ] && grep -q 'instance must be a number' "$work/out"; then echo "PASS a non-numeric instance is refused"; else echo "FAIL non-numeric instance: rc=$rc"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] || { echo "$fails failure(s)"; exit 1; }
echo "all runner restart cases passed"
