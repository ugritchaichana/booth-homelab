#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${CACHE_WAIT_SCRIPT:-$repo/iac/ansible/roles/cache_service/files/wait-for-address}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -f "$script" ] || { echo "ERROR: no script at $script" >&2; exit 2; }

cat > "$work/present" <<'EOF'
Main:
  +-- 0.0.0.0/0 3 0 5
     |-- 0.0.0.0
        /0 universe UNICAST
     +-- 10.99.17.0/24 2 0 2
        |-- 10.99.17.0
           /32 link BROADCAST
           /24 link UNICAST
        |-- 10.99.17.10
           /32 host LOCAL
        |-- 10.99.17.255
           /32 link BROADCAST
EOF
cat > "$work/absent" <<'EOF'
Main:
  +-- 0.0.0.0/0 3 0 5
     +-- 10.99.17.0/24 2 0 2
        |-- 10.99.17.0
           /32 link BROADCAST
           /24 link UNICAST
        |-- 10.99.17.1
           /32 host LOCAL
        |-- 10.99.17.10
           /32 link BROADCAST
EOF

run() { WAIT_FOR_ADDRESS_FIB_TRIE="$1" bash "$script" 10.99.17.10 "${2:-2}" > "$work/out.log" 2>&1; }

check() {
  run "$work/present" || { cat "$work/out.log" >&2; echo "FAIL: a configured address was not found" >&2; return 1; }
  if run "$work/absent"; then echo "FAIL: an address that is not a local /32 was accepted" >&2; return 1; fi
  grep -q "was not configured on any interface within 2 seconds" "$work/out.log" || { cat "$work/out.log" >&2; echo "FAIL: no timeout message for an absent address" >&2; return 1; }
  rc=0; run "$work/missing-file" || rc=$?
  [ "$rc" -eq 2 ] && grep -q "cannot read $work/missing-file" "$work/out.log" && ! grep -q "not configured" "$work/out.log" \
    || { cat "$work/out.log" >&2; echo "FAIL: an unreadable probe source must give the distinct message and exit 2" >&2; return 1; }
  return 0
}

if grep -Eq '(^|[^[:alnum:]_/-])ip +(-|addr|a )' "$script"; then
  echo "FAIL: the script calls ip, which needs a netlink socket the unit does not allow" >&2
  exit 1
fi

check || { echo "FAIL: the script does not meet its contract" >&2; exit 1; }
echo "ok: a local /32 is found, an absent one times out with its message, an unreadable source gives the distinct message"

if command -v systemd-run >/dev/null && [ -d /run/systemd/system ] && [ "$(id -u)" -eq 0 ]; then
  live="$(awk '$1 == "|--" { prev = $2 } $1 == "/32" && $2 == "host" && $3 == "LOCAL" && prev == "127.0.0.1" { print prev; exit }' /proc/net/fib_trie)"
  if [ -z "$live" ]; then
    echo "skip: no 127.0.0.1 /32 host LOCAL entry to probe in the sandbox run"
  elif systemd-run --wait --pipe -p RestrictAddressFamilies="AF_INET AF_INET6 AF_UNIX" bash "$script" 127.0.0.1 3 > "$work/sandbox.log" 2>&1; then
    echo "ok: the script finds a live address under RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX"
  else
    cat "$work/sandbox.log" >&2
    echo "FAIL: the script does not work under the unit's address-family restriction" >&2
    exit 1
  fi
else
  echo "skip: systemd-run with a running systemd is not available, the sandbox run did not execute"
fi

copy="$work/mutant"
sed 's/\$3 == "LOCAL"/$3 == "BROADCAST"/' "$script" > "$copy"
if cmp -s "$script" "$copy"; then echo "FAIL: the mutation changed nothing" >&2; exit 1; fi
script="$copy"
if check > "$work/mut.log" 2>&1; then
  echo "FAIL: the mutation that matches the wrong entry type was not caught" >&2
  exit 1
fi
echo "ok: mutation that matches the wrong entry type is rejected: $(grep -m1 FAIL "$work/mut.log")"
