#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
phases=" baseline after-pct-reboot after-pve-reboot after-host-reboot red-first "
guest=""
phase=""
targets="$here/targets.env"
wait_s=4

die() { echo "ERROR: $*" >&2; exit 2; }

while [ "$#" -gt 0 ]; do
  [ "$#" -ge 2 ] || die "usage: r15-probe.sh --guest lxc|vm --phase <phase> [--targets FILE] [--wait SECONDS]"
  case "$1" in
    --guest) guest="$2" ;;
    --phase) phase="$2" ;;
    --targets) targets="$2" ;;
    --wait) wait_s="$2" ;;
    *) die "unknown option $1" ;;
  esac
  shift 2
done

case "$guest" in lxc | vm) ;; *) die "--guest must be lxc or vm" ;; esac
case "$phases" in *" $phase "*) ;; *) die "--phase must be one of:$phases" ;; esac
[[ "$wait_s" =~ ^[0-9]{1,2}$ ]] || die "--wait must be 0 to 99 seconds"
[ -r "$targets" ] || die "no readable targets file at $targets"
command -v nc > /dev/null || die "nc is not installed"
command -v curl > /dev/null || die "curl is not installed"
command -v timeout > /dev/null || die "timeout is not installed"

tcp_state() {
  local kind="$1" host="$2" port="$3" out rc
  local fam=()
  [ "$kind" = tcp6 ] && fam=(-6)
  out="$(timeout "$((wait_s + 5))" nc "${fam[@]}" -z -w "$wait_s" "$host" "$port" 2>&1)"
  rc=$?
  if [ "$rc" -eq 0 ]; then echo open
  elif [ "$rc" -eq 124 ]; then echo dropped
  elif grep -qi 'refused' <<< "$out"; then echo refused
  elif grep -qiE 'unreachable|no route' <<< "$out"; then echo unreachable
  elif grep -qiE 'timed out|timeout' <<< "$out"; then echo dropped
  else echo error
  fi
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
  case "${scope:-}" in all | lxc | vm) ;; *) die "$label: scope must be all, lxc or vm" ;; esac
  case "${kind:-}" in tcp | tcp6) ;; *) die "$label: kind must be tcp or tcp6" ;; esac
  [[ "${host:-}" =~ ^[0-9A-Za-z:.%_-]+$ ]] || die "$label: invalid host"
  [[ "${port:-}" =~ ^[0-9]{1,5}$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || die "$label: invalid port"
  case "${expect:-}" in open | blocked) ;; *) die "$label: expect must be open or blocked" ;; esac
  case "${expect_red:-}" in open | blocked) ;; *) die "$label: expect_red must be open or blocked" ;; esac
  case "${control:-}" in True | False | -) ;; *) die "$label: control must be True, False or -" ;; esac
  [ "$scope" = all ] || [ "$scope" = "$guest" ] || continue

  want="$expect"
  [ "$phase" = red-first ] && want="$expect_red"
  actual="$(tcp_state "$kind" "$host" "$port")"

  if [ "$want" = open ]; then
    pos_total=$((pos_total + 1))
    if [ "$actual" = open ]; then
      pos_ok=$((pos_ok + 1)); verdict=PASS
    else
      verdict=FAIL; failed+=("$label expected open, got $actual")
    fi
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
done < "$targets"

code="$(curl -sS -m 8 -o /dev/null -w '%{http_code}' https://deb.debian.org/ 2> /dev/null)"
[ -n "$code" ] || code=000
if [ "$code" = 200 ]; then verdict=PASS; else verdict=FAIL; failed+=("egress_https expected 200, got $code"); fi
echo "PROBE egress_https curl deb.debian.org:443 200 $code $verdict"

if [ "$neg_total" -eq 0 ]; then failed+=("no negative row was measured: every one lacks a True control"); fi
for ((i = 0; i < ${#failed[@]}; i++)); do echo "FAILED ${failed[$i]}"; done

echo "SUMMARY negatives_blocked=$neg_ok/$neg_total positives_ok=$pos_ok/$pos_total egress_curl=$code"
[ "${#failed[@]}" -eq 0 ]
