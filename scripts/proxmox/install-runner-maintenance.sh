#!/usr/bin/env bash
# Owner-run on the PVE host as root. Idempotent; --dry-run prints every mutation without executing it.
set -uo pipefail

usage() {
    cat <<'USAGE'
Usage: install-runner-maintenance.sh [--dry-run] [--runner-cts "102 103"] [--minio-ct 104] [--restart-busy]

Installs, for each runner CT: the pre-job disk hook, the daily disk guard timer, the runner service
restart drop-in, and onboot. Installs the host watchdog (homelab-runner-watchdog.timer, every 5 min).

  --dry-run         print what would change; nothing is modified
  --runner-cts      space-separated runner CT ids (default: 102 103)
  --minio-ct        MinIO CT id, only gets onboot and start order (default: 104; "" to skip)
  --restart-busy    restart a runner service even while a job is running (default: defer it)

Run from a checkout of the repo (it reads scripts/runner-maintenance and scripts/proxmox/watchdog).

EPHEMERAL MODE: run this BEFORE `pct snapshot <CT> clean`, so the hook is baked into the snapshot.
A rollback to an older snapshot silently removes the hook. Ephemeral CTs (homelab-ephemeral-runner@<CT>
enabled) get no onboot and no restart; the supervisor owns their lifecycle.
USAGE
}

DRY=0
RUNNER_CTS="102 103"
MINIO_CT="104"
RESTART_BUSY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --runner-cts) RUNNER_CTS="${2:-}"; shift ;;
        --minio-ct) MINIO_CT="${2:-}"; shift ;;
        --restart-busy) RESTART_BUSY=1 ;;
        -h | --help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAINT="$SRC/scripts/runner-maintenance"
WD="$SRC/scripts/proxmox/watchdog"
RUNNER_USER="runner"
RUNNER_DIR="/home/$RUNNER_USER/actions-runner"
WD_CONF="/etc/default/homelab-runner-watchdog"
FAILS=0

[ "$(id -u)" -eq 0 ] || { echo "must run as root on the PVE host" >&2; exit 2; }
command -v pct >/dev/null 2>&1 || { echo "pct not found: run this on the PVE host" >&2; exit 2; }
for f in "$MAINT/disk-guard.sh" "$MAINT/job-started-hook.sh" "$MAINT/homelab-disk-guard.service" "$MAINT/homelab-disk-guard.timer" \
    "$MAINT/runner-restart.conf" "$WD/homelab-runner-watchdog.sh" "$WD/homelab-runner-watchdog.service" "$WD/homelab-runner-watchdog.timer"; do
    [ -f "$f" ] || { echo "missing source file: $f" >&2; exit 2; }
done

say() { printf '%s\n' "$*"; }
run() {
    if [ "$DRY" -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@" || { say "FAILED: $*"; FAILS=$((FAILS + 1)); return 1; }
}

ct_state() { pct status "$1" 2>/dev/null | awk '{print $2}'; }
is_ephemeral() { systemctl is-enabled --quiet "homelab-ephemeral-runner@$1.service" 2>/dev/null; }

CT_SCRIPT="$(mktemp)"
trap 'rm -f "$CT_SCRIPT"' EXIT
cat >"$CT_SCRIPT" <<'CTSCRIPT'
#!/bin/bash
set -u
user="$1"; rdir="$2"; restart_busy="$3"
hook=/opt/homelab/job-started-hook.sh
line="ACTIONS_RUNNER_HOOK_JOB_STARTED=$hook"
envf="$rdir/.env"
env_changed=0

job_running() {
    local c
    for c in /proc/[0-9]*/cmdline; do
        tr '\0' ' ' <"$c" 2>/dev/null | grep -q 'Runner\.Worker' && return 0
    done
    return 1
}

chmod 0755 /opt/homelab /opt/homelab/*.sh

if [ -d "$rdir" ]; then
    if [ "$(grep -c '^ACTIONS_RUNNER_HOOK_JOB_STARTED=' "$envf" 2>/dev/null)" = 1 ] && grep -qxF "$line" "$envf"; then
        echo "RESULT env=unchanged"
    else
        { grep -v '^ACTIONS_RUNNER_HOOK_JOB_STARTED=' "$envf" 2>/dev/null; printf '%s\n' "$line"; } >"$envf.new"
        if [ -f "$envf" ]; then
            chmod --reference="$envf" "$envf.new"
            chown --reference="$envf" "$envf.new"
        else
            chmod 0644 "$envf.new"
            chown "$user:$user" "$envf.new"
        fi
        mv "$envf.new" "$envf"
        env_changed=1
        echo "RESULT env=updated"
    fi
else
    echo "RESULT env=no-runner-dir"
fi

units="$(systemctl list-unit-files 'actions.runner.*.service' --no-legend 2>/dev/null | awk 'NF {print $1}')"
for u in $units; do
    d="/etc/systemd/system/$u.d"
    mkdir -p "$d"
    cmp -s /opt/homelab/runner-restart.conf "$d/restart.conf" || install -m 0644 /opt/homelab/runner-restart.conf "$d/restart.conf"
done

systemctl daemon-reload
systemctl enable --now homelab-disk-guard.timer >/dev/null 2>&1

for u in $units; do
    active="$(systemctl is-active "$u" 2>/dev/null)"
    if [ "$env_changed" -eq 1 ] || [ "$active" != active ]; then
        if [ "$active" = active ] && [ "$restart_busy" -eq 0 ] && job_running; then
            echo "RESULT restart=deferred-job-running unit=$u"
        elif systemctl restart "$u"; then
            echo "RESULT restart=done unit=$u"
        else
            echo "RESULT restart=FAILED unit=$u"
        fi
    fi
done
[ -n "$units" ] || echo "RESULT units=none (no persistent runner service; ephemeral or not enrolled)"
CTSCRIPT

install_ct() {
    local ct="$1" state f
    state="$(ct_state "$ct")"
    if [ -z "$state" ]; then
        say "CT $ct: does not exist; skipped"
        return
    fi
    if is_ephemeral "$ct"; then
        say "CT $ct: ephemeral supervisor enabled; no onboot, no service restart"
    else
        run pct set "$ct" --onboot 1 --startup order=2,up=15
    fi
    if [ "$state" != running ]; then
        if is_ephemeral "$ct"; then
            say "CT $ct: stopped and supervisor-owned; skipped (re-run while it is running, before snapshot clean)"
            return
        fi
        run pct start "$ct"
        if [ "$DRY" -eq 1 ]; then
            say "[dry-run] would wait for CT $ct to accept pct exec, then continue"
        else
            local i
            for i in $(seq 1 30); do
                pct exec "$ct" -- true >/dev/null 2>&1 && break
                sleep 2
            done
        fi
    fi

    say "CT $ct: installing runner maintenance"
    run pct exec "$ct" -- mkdir -p /opt/homelab
    for f in disk-guard.sh job-started-hook.sh; do
        run pct push "$ct" "$MAINT/$f" "/opt/homelab/$f" --perms 0755
    done
    run pct push "$ct" "$MAINT/runner-restart.conf" /opt/homelab/runner-restart.conf --perms 0644
    for f in homelab-disk-guard.service homelab-disk-guard.timer; do
        run pct push "$ct" "$MAINT/$f" "/etc/systemd/system/$f" --perms 0644
    done
    run pct push "$ct" "$CT_SCRIPT" /tmp/homelab-ct-install.sh --perms 0700
    if is_ephemeral "$ct"; then
        run pct exec "$ct" -- bash /tmp/homelab-ct-install.sh "$RUNNER_USER" "$RUNNER_DIR" 0
    else
        run pct exec "$ct" -- bash /tmp/homelab-ct-install.sh "$RUNNER_USER" "$RUNNER_DIR" "$RESTART_BUSY"
    fi
    run pct exec "$ct" -- rm -f /tmp/homelab-ct-install.sh
}

install_watchdog() {
    say "Host: installing runner watchdog"
    run install -m 0755 "$WD/homelab-runner-watchdog.sh" /usr/local/sbin/homelab-runner-watchdog.sh
    run install -m 0644 "$WD/homelab-runner-watchdog.service" /etc/systemd/system/homelab-runner-watchdog.service
    run install -m 0644 "$WD/homelab-runner-watchdog.timer" /etc/systemd/system/homelab-runner-watchdog.timer
    if [ ! -e "$WD_CONF" ]; then
        if [ "$DRY" -eq 1 ]; then
            say "[dry-run] create $WD_CONF with WATCHDOG_CTS"
        else
            printf 'WATCHDOG_CTS="%s"\n' "$(echo $MINIO_CT $RUNNER_CTS)" >"$WD_CONF"
        fi
    fi
    run systemctl daemon-reload
    run systemctl enable --now homelab-runner-watchdog.timer
}

status_table() {
    say ""
    say "Status ($([ "$DRY" -eq 1 ] && echo 'dry-run: current state, nothing installed' || echo 'after install'))"
    printf '%-6s %-9s %-7s %-14s %-9s %-5s %s\n' CT STATE ONBOOT STARTUP GUARD HOOK RUNNER-UNITS
    local ct state onboot startup guard hook units
    for ct in $MINIO_CT $RUNNER_CTS; do
        state="$(ct_state "$ct")"
        [ -n "$state" ] || { printf '%-6s %s\n' "$ct" absent; continue; }
        onboot="$(pct config "$ct" 2>/dev/null | awk -F': ' '$1=="onboot"{print $2}')"
        startup="$(pct config "$ct" 2>/dev/null | awk -F': ' '$1=="startup"{print $2}')"
        guard="-"
        hook="-"
        units="-"
        if [ "$state" = running ] && [ "$ct" != "$MINIO_CT" ]; then
            guard="$(pct exec "$ct" -- systemctl is-enabled homelab-disk-guard.timer 2>/dev/null || true)"
            hook="$(pct exec "$ct" -- grep -c '^ACTIONS_RUNNER_HOOK_JOB_STARTED=' "$RUNNER_DIR/.env" 2>/dev/null || true)"
            units="$(pct exec "$ct" -- systemctl list-units 'actions.runner.*.service' --no-legend --plain 2>/dev/null | awk '{print $1"="$3}' | paste -sd, - || true)"
        fi
        printf '%-6s %-9s %-7s %-14s %-9s %-5s %s\n' "$ct" "$state" "${onboot:-0}" "${startup:--}" "${guard:--}" "${hook:--}" "${units:--}"
    done
    printf 'host   watchdog timer: %s\n' "$(systemctl is-enabled homelab-runner-watchdog.timer 2>/dev/null || echo not-installed)"
}

if [ -n "$MINIO_CT" ] && [ -n "$(ct_state "$MINIO_CT")" ]; then
    run pct set "$MINIO_CT" --onboot 1 --startup order=1,up=30
fi
for ct in $RUNNER_CTS; do
    install_ct "$ct"
done
install_watchdog
status_table

if [ "$FAILS" -gt 0 ]; then
    say "$FAILS step(s) failed; see FAILED lines above"
    exit 1
fi
