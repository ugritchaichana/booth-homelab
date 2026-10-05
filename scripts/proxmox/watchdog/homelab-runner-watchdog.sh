#!/usr/bin/env bash
# PVE host watchdog: start stopped CTs and restart dead runner services; one attempt per CT per timer tick.
set -uo pipefail

CTS="${WATCHDOG_CTS:-102 103 104}"
TIMEOUT="${WATCHDOG_EXEC_TIMEOUT:-60}"

log() { printf 'homelab-watchdog: %s\n' "$*"; }

exec 9>/run/homelab-runner-watchdog.lock
flock -n 9 || { log "previous pass still running; skipping"; exit 0; }

for bin in pct systemctl timeout; do
    command -v "$bin" >/dev/null 2>&1 || { log "required command missing: $bin"; exit 0; }
done

runner_units() {
    timeout "$TIMEOUT" pct exec "$1" -- systemctl list-unit-files 'actions.runner.*.service' --no-legend 2>/dev/null | awk 'NF {print $1}'
}

unit_alive() {
    local state
    state="$(timeout "$TIMEOUT" pct exec "$1" -- systemctl show -p ActiveState --value "$2" 2>/dev/null | tr -d '[:space:]')"
    case "$state" in active | activating | reloading) return 0 ;; *) return 1 ;; esac
}

actions=0
for ct in $CTS; do
    case "$ct" in '' | *[!0-9]*) log "ct=$ct ignored: not numeric"; continue ;; esac

    if systemctl is-enabled --quiet "homelab-ephemeral-runner@${ct}.service" 2>/dev/null; then
        continue
    fi

    status="$(pct status "$ct" 2>/dev/null | awk '{print $2}')"
    if [ -z "$status" ]; then
        log "ct=$ct does not exist; skipping"
        continue
    fi

    if [ "$status" != running ]; then
        if timeout 180 pct start "$ct" >/dev/null 2>&1; then
            log "ct=$ct was $status; pct start ok"
        else
            log "ct=$ct was $status; pct start FAILED"
        fi
        actions=$((actions + 1))
        continue
    fi

    units="$(runner_units "$ct")"
    [ -n "$units" ] || continue

    alive=0
    for u in $units; do
        unit_alive "$ct" "$u" && alive=1
    done
    [ "$alive" -eq 1 ] && continue

    for u in $units; do
        if timeout "$TIMEOUT" pct exec "$ct" -- systemctl is-enabled --quiet "$u" 2>/dev/null; then
            if timeout "$TIMEOUT" pct exec "$ct" -- systemctl restart "$u" >/dev/null 2>&1; then
                log "ct=$ct no runner service active; restarted $u"
            else
                log "ct=$ct no runner service active; restart of $u FAILED"
            fi
            actions=$((actions + 1))
        fi
    done
done

log "pass complete actions=$actions cts=\"$CTS\""
exit 0
