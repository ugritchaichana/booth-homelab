#!/usr/bin/env bash
# shellcheck shell=bash

api="${GITHUB_API_URL:-https://api.github.com}"
lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fetch() {
  printf 'Authorization: Bearer %s\n' "$2" | curl -sS -o "$3" -w '%{http_code}' --max-time 15 -H @- \
    -H 'Accept: application/vnd.github+json' "$1" 2> "$3.err" || true
}

why() {
  local message
  message="$(jq -r '.message? // empty' "$1" 2> /dev/null | head -c 200 || true)"
  echo "${message:-$(head -c 200 "$1.err" 2> /dev/null || true)}"
}

field() {
  sed -n "s/^$1=//p" <<< "$2"
}

attempt_env() {
  if [ -z "$1" ] || [ -n "$(field error "$1")" ]; then
    return 0
  fi
  if [ "$(field proxmox "$1")" = true ]; then
    echo proxmox
  else
    echo hosted
  fi
}

classify_attempt() {
  local run_id="$1" attempt="$2" dir="$3" code id ids
  mkdir -p "$dir/annotations"
  code="$(fetch "$api/repos/$REPOSITORY/actions/runs/$run_id/attempts/$attempt/jobs?per_page=100" "$GH_TOKEN" "$dir/jobs.json")"
  if [ "$code" != 200 ]; then
    echo "error=jobs of attempt $attempt returned HTTP $code: $(why "$dir/jobs.json")"
    return 0
  fi
  ids="$(jq -r '.jobs[] | select(.conclusion == "failure" or .conclusion == "cancelled") | .id' "$dir/jobs.json" 2> "$dir/jq.err" | tr -d '\r')" || { echo "error=jobs of attempt $attempt are not readable: $(head -c 200 "$dir/jq.err")"; return 0; }
  for id in $ids; do
    code="$(fetch "$api/repos/$REPOSITORY/check-runs/$id/annotations" "$GH_TOKEN" "$dir/annotations/$id.json")"
    if [ "$code" != 200 ]; then
      echo "error=annotations of attempt $attempt returned HTTP $code: $(why "$dir/annotations/$id.json")"
      return 0
    fi
  done
  python3 "$lib_dir/runner_route.py" classify --jobs "$dir/jobs.json" --annotations-dir "$dir/annotations"
}
