#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${CACHE_VERIFY_CAS_SCRIPT:-$repo/iac/ansible/roles/cache_service/files/verify-cas}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -f "$script" ] || { echo "ERROR: no script at $script" >&2; exit 2; }

sha() { printf '%s' "$1" | sha256sum | cut -d' ' -f1; }

build() {
  rm -rf "$work/data" "$work/quarantine"
  good_body="a blob that arrived whole"
  full_body="a blob that was cut short by a crash"
  good="$(sha "$good_body")"
  full="$(sha "$full_body")"
  mkdir -p "$work/data/cas.v2/${good:0:2}" "$work/data/cas.v2/${full:0:2}" "$work/data/cas.v2/zz" "$work/data/ac.v2/00"
  printf '%s' "$good_body" > "$work/data/cas.v2/${good:0:2}/$good-${#good_body}-1111"
  printf '%s' "${full_body:0:12}" > "$work/data/cas.v2/${full:0:2}/$full-${#full_body}-2222"
  printf '%s' "not a content address" > "$work/data/cas.v2/zz/not-a-hash-file"
  printf '%s' "an action result that does not hash to its name" > "$work/data/ac.v2/00/$(sha ac)-3333"
}

run() { bash "$script" "$work/data" "$work/quarantine" "${1:-3}" "${2:-1000}" > "$work/out.log" 2>&1; }

fail() { cat "$work/out.log" >&2; echo "FAIL: $1" >&2; return 1; }

check() {
  build
  run || { fail "the sweep exited non-zero on a readable data dir"; return 1; }
  [ -f "$work/data/cas.v2/${good:0:2}/$good-${#good_body}-1111" ] || { fail "the good blob was moved"; return 1; }
  [ ! -e "$work/data/cas.v2/${full:0:2}/$full-${#full_body}-2222" ] || { fail "the truncated blob is still served from cas.v2"; return 1; }
  [ -f "$work/quarantine/$full-${#full_body}-2222" ] || { fail "the truncated blob is not in the quarantine"; return 1; }
  [ -f "$work/data/cas.v2/zz/not-a-hash-file" ] || { fail "a non-hash name was touched"; return 1; }
  [ -f "$work/data/ac.v2/00/$(sha ac)-3333" ] || { fail "ac.v2 was touched"; return 1; }
  grep -q "quarantined ${full:0:12} size=12" "$work/out.log" || { fail "no log line for the quarantined blob"; return 1; }
  grep -qE "checked=2 quarantined=1 deleted=0 skipped=1 unreadable=0 seconds=[0-9]+" "$work/out.log" || { fail "the summary line is wrong"; return 1; }

  build
  run 3 5 || { fail "the sweep exited non-zero with a small size cap"; return 1; }
  [ ! -e "$work/quarantine/$full-${#full_body}-2222" ] && grep -q "deleted ${full:0:12}" "$work/out.log" || { fail "a blob above the size cap was not deleted"; return 1; }

  build
  mkdir -p "$work/quarantine"
  for n in 1 2 3; do : > "$work/quarantine/old$n"; touch -d "2020-01-0$n" "$work/quarantine/old$n"; done
  run 2 || { fail "the sweep exited non-zero with old quarantine files"; return 1; }
  [ "$(find "$work/quarantine" -type f | wc -l)" -eq 2 ] && [ -f "$work/quarantine/$full-${#full_body}-2222" ] && [ ! -e "$work/quarantine/old1" ] || { fail "the quarantine was not pruned to the newest 2"; return 1; }

  rm -rf "$work/data"
  if run; then fail "a missing data dir did not fail the sweep"; return 1; fi
  return 0
}

check || { echo "FAIL: the sweep does not meet its contract" >&2; exit 1; }
echo "ok: the truncated blob is quarantined, the good blob stays, other names and ac.v2 are untouched, a missing data dir fails"

copy="$work/mutant"
sed 's/\[ "\$got" = "\$want" \] && continue/[ "$got" = "$name" ] \&\& continue/' "$script" > "$copy"
if cmp -s "$script" "$copy"; then echo "FAIL: the mutation changed nothing" >&2; exit 1; fi
script="$copy"
if check > "$work/mut.log" 2>&1; then
  echo "FAIL: the mutation that compares the wrong field was not caught" >&2
  exit 1
fi
echo "ok: mutation that compares the wrong field is rejected: $(grep -m1 FAIL "$work/mut.log")"
