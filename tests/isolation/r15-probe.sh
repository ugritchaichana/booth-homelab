#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
phases=" baseline after-pct-reboot after-pve-reboot after-host-reboot red-first "
guest=""
phase=""
targets="$here/targets.env"
wait_s=4
via_route=""

die() { echo "ERROR: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || die "usage: r15-probe.sh --guest lxc|vm|cache --phase <phase> [--targets FILE] [--wait SECONDS]"
  case "$1" in
    --guest) guest="$2" ;;
    --phase) phase="$2" ;;
    --targets) targets="$2" ;;
    --wait) wait_s="$2" ;;
    *) die "unknown option $1" ;;
  esac
  shift 2
done

case "$guest" in lxc | vm | cache) ;; *) die "--guest must be lxc, vm or cache" ;; esac
case "$phases" in *" $phase "*) ;; *) die "--phase must be one of:$phases" ;; esac
[[ "$wait_s" =~ ^[1-9][0-9]?$ ]] || die "--wait must be 1 to 99 seconds"
[ -r "$targets" ] || die "no readable targets file at $targets"
command -v curl > /dev/null || die "curl is not installed"
command -v timeout > /dev/null || die "timeout is not installed"
cache_addr="${CACHE_ADDR:-}"
cache_port="${CACHE_PORT:-}"
if [ -n "$cache_addr$cache_port" ]; then
  [[ "$cache_addr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "CACHE_ADDR must be an IPv4 address"
  [[ "$cache_port" =~ ^[0-9]{1,5}$ ]] && [ "$cache_port" -ge 1 ] && [ "$cache_port" -le 65535 ] || die "CACHE_PORT must be 1 to 65535"
fi

drop_via_route() {
  [ -z "$via_route" ] || ip route del "$via_route" 2> /dev/null
  via_route=""
}
trap drop_via_route EXIT

# open: connected; refused: answered at once with a reset; dropped: no answer before the timeout.
tcp_state() {
  local host="$1" port="$2" err rc
  err="$(timeout "$wait_s" bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then echo open
  elif [ "$rc" -eq 124 ]; then echo dropped
  elif grep -qiE 'unreachable|no route' <<< "$err"; then echo unreachable
  elif grep -qiE 'not known|resolve|invalid' <<< "$err"; then echo error
  else echo refused
  fi
}

# Sends the peer's traffic through the gateway, the path that bypasses port isolation.
tcp_state_via_gateway() {
  local host="$1" port="$2" gw
  gw="$(ip -4 route show default | awk '{for (i = 1; i < NF; i++) if ($i == "via") {print $(i + 1); exit}}')"
  if [ -z "$gw" ] || ! ip route replace "$host/32" via "$gw" 2> /dev/null; then echo error; return; fi
  via_route="$host/32"
  tcp_state "$host" "$port"
  drop_via_route
}

evaluate() {
  local label="$1" kind="$2" host="$3" port="$4" expect="$5" expect_red="$6" control="$7" want actual verdict
  want="$expect"
  [ "$phase" = red-first ] && want="$expect_red"
  if [ "$kind" = tcpvia ]; then
    [ "$(id -u)" -eq 0 ] && command -v ip > /dev/null || die "$label: tcpvia needs root and ip"
    actual="$(tcp_state_via_gateway "$host" "$port")"
  else
    actual="$(tcp_state "$host" "$port")"
  fi

  if [ "$want" = open ] || [ "$want" = refused ]; then
    pos_total=$((pos_total + 1))
    if [ "$actual" = "$want" ]; then
      pos_ok=$((pos_ok + 1)); verdict=PASS
    else
      verdict=FAIL; failed+=("$label expected $want, got $actual")
    fi
  elif [ "$actual" = open ] || [ "$actual" = refused ]; then
    neg_total=$((neg_total + 1))
    verdict=FAIL; failed+=("$label expected blocked, got $actual")
  elif [ "$control" != True ]; then
    verdict="NOT MEASURED"
  else
    neg_total=$((neg_total + 1))
    if [ "$actual" = dropped ] || [ "$actual" = unreachable ]; then
      neg_ok=$((neg_ok + 1)); verdict=PASS
    else
      verdict=FAIL; failed+=("$label expected blocked, got $actual")
    fi
  fi
  echo "PROBE $label $kind $host:$port $want $actual $verdict"
  last_actual="$actual"
}

neg_total=0
neg_ok=0
pos_total=0
pos_ok=0
failed=()

echo "RUN guest=$guest phase=$phase host=$(hostname) utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

while IFS='=' read -r label rest || [ -n "$label" ]; do
  case "$label" in '' | '#'*) continue ;; esac
  [[ "$label" =~ ^[a-z0-9_]+$ ]] || die "invalid label '$label' in $targets"
  read -r scope kind host port expect expect_red control extra <<< "$rest"
  [ -z "${extra:-}" ] || die "$label: expected 7 fields after '='"
  case "${scope:-}" in all | runner | lxc | vm | cache) ;; *) die "$label: scope must be all, runner, lxc, vm or cache" ;; esac
  case "${kind:-}" in tcp | tcp6 | tcpvia) ;; *) die "$label: kind must be tcp, tcp6 or tcpvia" ;; esac
  [[ "${host:-}" =~ ^[0-9A-Za-z:.%_-]+$ ]] || die "$label: invalid host"
  [[ "${port:-}" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "$label: invalid port"
  case "${expect:-}" in open | blocked) ;; *) die "$label: expect must be open or blocked" ;; esac
  case "${expect_red:-}" in open | blocked | refused) ;; *) die "$label: expect_red must be open, blocked or refused" ;; esac
  case "${control:-}" in True | False | -) ;; *) die "$label: control must be True, False or -" ;; esac
  [ "$scope" = all ] || [ "$scope" = "$guest" ] || { [ "$scope" = runner ] && [ "$guest" != cache ]; } || continue

  evaluate "$label" "$kind" "$host" "$port" "$expect" "$expect_red" "$control"
done < "$targets"

if [ -n "$cache_addr" ] && [ "$guest" != cache ]; then
  evaluate cache_port_reachable tcp "$cache_addr" "$cache_port" open open -
  cache_control=False
  [ "$last_actual" = open ] && cache_control=True
  evaluate cache_ssh_blocked tcp "$cache_addr" 22 blocked open "$cache_control"
fi

code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' https://deb.debian.org/ 2> /dev/null)"
[ -n "$code" ] || code=000
if [ "$code" = 200 ]; then verdict=PASS; else verdict=FAIL; failed+=("egress_https expected 200, got $code"); fi
echo "PROBE egress_https curl deb.debian.org:443 200 $code $verdict"

if [ "$neg_total" -eq 0 ]; then failed+=("no negative row was measured: every one lacks a True control"); fi
for ((i = 0; i < ${#failed[@]}; i++)); do echo "FAILED ${failed[$i]}"; done

echo "SUMMARY negatives_blocked=$neg_ok/$neg_total positives_ok=$pos_ok/$pos_total egress_curl=$code"
[ "${#failed[@]}" -eq 0 ]
