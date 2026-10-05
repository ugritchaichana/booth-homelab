#!/usr/bin/env bash
# Root-run daily disk guard inside a runner CT; always exits 0.
set -u

GIB=1073741824
num() { case "${1:-}" in '' | *[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }

PRUNE_BELOW=$(($(num "${HOMELAB_PRUNE_BELOW_GIB:-}" 3) * GIB))
HARD_FLOOR=$(($(num "${HOMELAB_HARD_FLOOR_GIB:-}" 1) * GIB))
RUNNER_USER="${HOMELAB_RUNNER_USER:-runner}"
HOOK="${HOMELAB_HOOK:-/opt/homelab/job-started-hook.sh}"
JOURNAL_MAX="${HOMELAB_JOURNAL_MAX:-200M}"

log() { printf 'homelab-disk-guard: %s\n' "$*"; }
free_bytes() {
    local v
    v="$(df --output=avail -B1 / 2>/dev/null | tail -n 1 | tr -d '[:space:]')"
    case "$v" in '' | *[!0-9]*) return 1 ;; esac
    printf '%s' "$v"
}
job_running() {
    local c
    for c in /proc/[0-9]*/cmdline; do
        tr '\0' ' ' <"$c" 2>/dev/null | grep -q 'Runner\.Worker' && return 0
    done
    return 1
}

step_runner_prune() {
    local home
    home="$(getent passwd "$RUNNER_USER" | cut -d: -f6)"
    [ -n "$home" ] && [ -x "$HOOK" ] || return 0
    runuser -u "$RUNNER_USER" -- env -u TMPDIR HOME="$home" HOMELAB_PRUNE_BELOW_GIB=$((PRUNE_BELOW / GIB)) HOMELAB_HARD_FLOOR_GIB=$((HARD_FLOOR / GIB)) "$HOOK" || true
}
step_journal() { command -v journalctl >/dev/null 2>&1 && journalctl --vacuum-size="$JOURNAL_MAX" >/dev/null 2>&1 || true; }
step_apt() { command -v apt-get >/dev/null 2>&1 && apt-get clean >/dev/null 2>&1 || true; }
step_tmp() { find /tmp -xdev -mindepth 1 -type f -mtime +2 -atime +2 ! -path '/tmp/systemd-private-*' -delete 2>/dev/null || true; }
step_docker() {
    command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 || return 0
    docker system prune -af >/dev/null 2>&1 || true
    local now
    now="$(free_bytes)" || return 0
    [ "$now" -lt "$HARD_FLOOR" ] && docker system prune -af --volumes >/dev/null 2>&1 || true
}

start="$(free_bytes)" || { log "cannot measure free space on /; nothing done"; exit 0; }
log "free=$start bytes on / threshold=$PRUNE_BELOW hard_floor=$HARD_FLOOR"

busy=0
job_running && busy=1
[ "$busy" -eq 1 ] && log "runner job active; skipping runner-user prune and docker prune"

for step in runner_prune journal apt tmp docker; do
    case "$step" in runner_prune | docker) [ "$busy" -eq 1 ] && continue ;; esac
    if [ "$step" = docker ]; then
        now="$(free_bytes)" || break
        [ "$now" -ge "$PRUNE_BELOW" ] && { log "step=docker skipped free=$now is above threshold"; continue; }
    fi
    before="$(free_bytes)" || break
    "step_$step" || true
    after="$(free_bytes)" || break
    log "step=$step free_before=$before free_after=$after"
done

end="$(free_bytes)" || exit 0
log "done free_start=$start free_end=$end"
[ "$end" -lt "$HARD_FLOOR" ] && log "WARNING: / still below hard floor $HARD_FLOOR bytes; free disk or resize the CT rootfs"
exit 0
