#!/usr/bin/env bash
# Pre-job disk prune as the runner user; exit 1 only below the hard floor.
set -u

GIB=1073741824
num() { case "${1:-}" in '' | *[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

PRUNE_BELOW=$(($(num "${HOMELAB_PRUNE_BELOW_GIB:-}" 3) * GIB))
HARD_FLOOR=$(($(num "${HOMELAB_HARD_FLOOR_GIB:-}" 1) * GIB))
TEMP_AGE_MIN="$(num "${HOMELAB_TEMP_AGE_MIN:-}" 60)"
ACTIONS_AGE_MIN="$(num "${HOMELAB_ACTIONS_AGE_MIN:-}" 30)"

HOME_DIR="${HOME:-/home/runner}"
RUNNER_DIR="${HOMELAB_RUNNER_DIR:-$HOME_DIR/actions-runner}"
WORK_DIR="$RUNNER_DIR/_work"
ME="$(id -un 2>/dev/null || printf runner)"

MEASURE_PATH=/
for p in "$HOME_DIR" "$RUNNER_DIR" "$WORK_DIR"; do [ -d "$p" ] && MEASURE_PATH="$p"; done

log() { printf 'homelab-hook: %s\n' "$*"; }

free_bytes() {
    local v
    v="$(df --output=avail -B1 "$MEASURE_PATH" 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
    case "$v" in '' | *[!0-9]*) return 1 ;; esac
    printf '%s' "$v"
}

step_temp() { [ -d "$WORK_DIR/_temp" ] && find "$WORK_DIR/_temp" -xdev -mindepth 1 -mmin "+$TEMP_AGE_MIN" ! -path '*/_runner_file_commands*' -delete 2>/dev/null || true; }
step_actions() { [ -d "$WORK_DIR/_actions" ] && find "$WORK_DIR/_actions" -xdev -mindepth 1 -mmin "+$ACTIONS_AGE_MIN" -delete 2>/dev/null || true; }
step_diag() { [ -d "$RUNNER_DIR/_diag" ] && find "$RUNNER_DIR/_diag" -xdev -mindepth 1 -maxdepth 1 -type f -name '*.log' -mtime +7 -delete 2>/dev/null || true; }
step_npm() { [ -d "$HOME_DIR/.npm/_cacache" ] && find "$HOME_DIR/.npm/_cacache" -xdev -mindepth 1 -delete 2>/dev/null || true; }
step_nuget() {
    [ -d "$HOME_DIR/.nuget/packages" ] && find "$HOME_DIR/.nuget/packages" -xdev -mindepth 1 -delete 2>/dev/null || true
    [ -d "$HOME_DIR/.local/share/NuGet" ] && find "$HOME_DIR/.local/share/NuGet" -xdev -mindepth 1 -delete 2>/dev/null || true
}
step_tmp() {
    local t
    for t in "${TMPDIR:-/tmp}" /tmp; do
        case "$t" in */_work | */_work/*) continue ;; esac
        [ -d "$t" ] && find "$t" -xdev -mindepth 1 -user "$ME" -mtime +2 ! -path '*/_work/*' -delete 2>/dev/null || true
    done
}

cur="$(free_bytes)" || { log "cannot measure free space on $MEASURE_PATH; skipping prune"; exit 0; }

if [ "$cur" -ge "$PRUNE_BELOW" ]; then
    log "free=$cur bytes on $MEASURE_PATH is above threshold=$PRUNE_BELOW; nothing to prune"
    exit 0
fi

log "free=$cur bytes on $MEASURE_PATH is below threshold=$PRUNE_BELOW; pruning"

for step in temp actions diag npm nuget tmp; do
    before="$(free_bytes)" || break
    "step_$step" || true
    after="$(free_bytes)" || break
    log "step=$step free_before=$before free_after=$after"
    cur="$after"
    [ "$cur" -ge "$PRUNE_BELOW" ] && break
done

if [ "$cur" -lt "$HARD_FLOOR" ]; then
    log "FATAL: $MEASURE_PATH has $cur bytes free after pruning, below hard floor $HARD_FLOOR; free disk or resize the CT rootfs"
    exit 1
fi

exit 0
