#!/usr/bin/env bash
# One CT per instance: rollback to snapshot clean, mint a JIT runner, run one job, repeat.
set -uo pipefail
set +x
umask 077

CT="${1:-}"
CONF="/etc/homelab/ephemeral-runner-${CT}.conf"
ENV_FILE="/etc/homelab/runner-supervisor.env"
MIN_JOB_SECONDS=60
BACKOFF_START=30
BACKOFF_MAX=300
TMP_JIT=""

log() { printf '%s [ct-%s] %s\n' "$(date -u +%FT%TZ)" "$CT" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
cleanup() { [[ -n "$TMP_JIT" ]] && rm -f "$TMP_JIT"; }
trap cleanup EXIT

[[ "$CT" =~ ^[0-9]+$ ]] || die "usage: $0 <ct-id>"
for bin in pct curl jq; do
    command -v "$bin" >/dev/null 2>&1 || die "required command missing on this host: $bin"
done

[[ -r "$CONF" ]] || die "missing per-CT config: $CONF"
[[ -r "$ENV_FILE" ]] || die "missing $ENV_FILE (root-owned, mode 0600, defines GITHUB_RUNNER_ADMIN_TOKEN)"
perm="$(stat -c '%a' "$ENV_FILE")"
[[ "$perm" == "600" || "$perm" == "400" ]] || die "$ENV_FILE must be mode 0600 or 0400 (found $perm)"

# shellcheck disable=SC1090
. "$CONF"
# shellcheck disable=SC1090
. "$ENV_FILE"

GITHUB_REPO="${GITHUB_REPO:-}"
RUNNER_NAME_PREFIX="${RUNNER_NAME_PREFIX:-}"
RUNNER_LABELS="${RUNNER_LABELS:-}"
RUNNER_GROUP_ID="${RUNNER_GROUP_ID:-1}"
RUNNER_USER="${RUNNER_USER:-runner}"
RUNNER_DIR="${RUNNER_DIR:-/home/${RUNNER_USER}/actions-runner}"
JIT_FILE="/home/${RUNNER_USER}/.jit"

[[ -n "$GITHUB_REPO" ]] || die "GITHUB_REPO is not set in $CONF"
[[ -n "$RUNNER_NAME_PREFIX" ]] || die "RUNNER_NAME_PREFIX is not set in $CONF"
[[ -n "$RUNNER_LABELS" ]] || die "RUNNER_LABELS is not set in $CONF"
[[ "$RUNNER_GROUP_ID" =~ ^[0-9]+$ ]] || die "RUNNER_GROUP_ID must be numeric"
[[ -n "${GITHUB_RUNNER_ADMIN_TOKEN:-}" ]] || die "GITHUB_RUNNER_ADMIN_TOKEN is unset or empty in $ENV_FILE"

backoff=$BACKOFF_START

wait_before_retry() {
    log "retrying in ${backoff}s: $1"
    sleep "$backoff"
    backoff=$((backoff * 2))
    if ((backoff > BACKOFF_MAX)); then backoff=$BACKOFF_MAX; fi
}

wait_for_network() {
    local i
    for i in $(seq 1 30); do
        pct exec "$CT" -- getent hosts github.com >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

mint_jit_config() {
    local name body resp code payload
    name="${RUNNER_NAME_PREFIX}-${CT}-$(date +%s)"
    body="$(jq -nc --arg name "$name" --argjson group "$RUNNER_GROUP_ID" \
        --argjson labels "$(printf '%s' "$RUNNER_LABELS" | jq -R 'split(",")')" \
        '{name: $name, runner_group_id: $group, labels: $labels, work_folder: "_work"}')" || return 1
    resp="$(printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_RUNNER_ADMIN_TOKEN" |
        curl -sS --max-time 30 --config - -X POST \
            -H 'Accept: application/vnd.github+json' \
            -H 'X-GitHub-Api-Version: 2022-11-28' \
            -H 'Content-Type: application/json' \
            -d "$body" -w '\n%{http_code}' \
            "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/generate-jitconfig")" ||
        { log "generate-jitconfig request failed"; return 1; }
    code="${resp##*$'\n'}"
    payload="${resp%$'\n'*}"
    if [[ "$code" != "201" ]]; then
        log "generate-jitconfig returned HTTP ${code}: $(jq -r '.message // empty' <<<"$payload" 2>/dev/null)"
        return 1
    fi
    jq -re '.encoded_jit_config' <<<"$payload"
}

hand_off_jit_config() {
    TMP_JIT="$(mktemp -p /run jit.XXXXXX)" || return 1
    printf '%s' "$1" >"$TMP_JIT"
    pct push "$CT" "$TMP_JIT" "$JIT_FILE" --perms 0600 --user "$RUNNER_USER" --group "$RUNNER_USER"
    local rc=$?
    rm -f "$TMP_JIT"
    TMP_JIT=""
    return $rc
}

while true; do
    pct status "$CT" 2>/dev/null | grep -q 'status: running' && pct stop "$CT" >/dev/null 2>&1
    pct rollback "$CT" clean || die "pct rollback to snapshot clean failed"

    if ! pct start "$CT"; then wait_before_retry "pct start failed"; continue; fi
    if ! wait_for_network; then wait_before_retry "CT did not resolve github.com"; continue; fi

    jit="$(mint_jit_config)" || { wait_before_retry "could not mint JIT config"; continue; }
    if ! hand_off_jit_config "$jit"; then
        jit=""
        wait_before_retry "could not place JIT config in CT"
        continue
    fi
    jit=""

    log "runner starting"
    started=$(date +%s)
    pct exec "$CT" -- su -l "$RUNNER_USER" -c \
        "cd '${RUNNER_DIR}' && J=\$(cat '${JIT_FILE}') && rm -f '${JIT_FILE}' && exec ./run.sh --jitconfig \"\$J\""
    rc=$?
    elapsed=$(($(date +%s) - started))
    log "runner exited rc=${rc} after ${elapsed}s"

    if ((rc != 0 && elapsed < MIN_JOB_SECONDS)); then
        wait_before_retry "runner exited early"
    else
        backoff=$BACKOFF_START
    fi
done
