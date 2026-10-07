#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$repo/tests/isolation/r15-probe.sh"
work="$(mktemp -d)"
listener=""
trap '[ -z "$listener" ] || kill "$listener" 2> /dev/null; rm -rf "$work"' EXIT
mkdir "$work/bin" "$work/fake-timeout" "$work/fake-bash"
fails=0

# curl, id and ip are always stubbed; timeout is stubbed only where a verdict must be forced.
cat > "$work/bin/curl" << 'STUB'
#!/bin/sh
if [ "${STUB_CURL_CODE:-200}" = offline ]; then printf '000'; exit 28; fi
printf '%s' "${STUB_CURL_CODE:-200}"
STUB
cat > "$work/bin/id" << 'STUB'
#!/bin/sh
echo "${STUB_UID:-0}"
STUB
cat > "$work/bin/ip" << 'STUB'
#!/bin/sh
case "$*" in
  "-4 route show default") echo "default via 10.99.16.1 dev eth0" ;;
  *) echo "ip $*" >> "$STUB_IP_LOG" ;;
esac
STUB
cat > "$work/fake-timeout/timeout" << 'STUB'
#!/usr/bin/env bash
host="${*: -2:1}"
port="${*: -1}"
state="$(awk -v k="$host:$port" '$1 == k {print $2}' "$STUB_TCP_MAP")"
case "${state:-dropped}" in
  open) exit 0 ;;
  refused) echo "bash: connect: Connection refused" >&2; exit 1 ;;
  unreachable) echo "bash: connect: Network is unreachable" >&2; exit 1 ;;
  error) echo "bash: $host: Name or service not known" >&2; exit 1 ;;
  *) exit 124 ;;
esac
STUB
cat > "$work/fake-bash/bash" << 'STUB'
#!/usr/bin/env sh
exec sleep 30
STUB
chmod +x "$work/bin/"* "$work/fake-timeout/timeout" "$work/fake-bash/bash"

cat > "$work/targets.env" << 'ROWS'
# label=scope kind host port expect expect_red control
egress_public_https=all tcp 1.1.1.1 443 open open -
gateway_ssh=all tcp 192.0.2.1 22 blocked open True
lxc_to_vm_direct=lxc tcp 192.0.2.22 22 blocked blocked True
lxc_to_vm_via_gateway=lxc tcpvia 192.0.2.22 22 blocked blocked True
vm_to_lxc_ssh=vm tcp 192.0.2.21 22 blocked open True
windows_host_smb=all tcp 198.51.100.1 445 blocked blocked True
unpaired_dns=all tcp 198.51.100.2 53 blocked blocked False
ROWS

holds="1.1.1.1:443 open"
export STUB_TCP_MAP="$work/tcp.map" STUB_IP_LOG="$work/ip.log"
: > "$STUB_IP_LOG"

run() {
  PATH="$work/fake-timeout:$work/bin:$PATH" "$BASH" "$probe" --targets "$work/targets.env" "$@" > "$work/out.txt" 2>&1 && rc=0 || rc=$?
}

expect() {
  local name="$1" want_rc="$2" pattern="$3"
  if [ "$rc" -eq "$want_rc" ] && grep -qE -- "$pattern" "$work/out.txt"; then
    echo "ok   $name"
  else
    echo "FAIL $name (rc=$rc, wanted rc=$want_rc and /$pattern/)"
    sed 's/^/     | /' "$work/out.txt"
    fails=$((fails + 1))
  fi
}

printf '%s\n' "$holds" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "all hold: exit 0 and the summary" 0 '^SUMMARY negatives_blocked=4/4 positives_ok=1/1 egress_curl=200$'
expect "an unpaired row that is dropped is not measured" 0 '^PROBE unpaired_dns tcp 198.51.100.2:53 blocked dropped NOT MEASURED$'
expect "the other guest's row is skipped" 0 '^PROBE lxc_to_vm_direct '
grep -q 'vm_to_lxc_ssh' "$work/out.txt" && { echo "FAIL the vm row ran on the lxc guest"; fails=$((fails + 1)); }
if [ "$(cat "$STUB_IP_LOG")" = "$(printf 'ip route replace 192.0.2.22/32 via 10.99.16.1\nip route del 192.0.2.22/32')" ]; then
  echo "ok   the via-gateway row adds its route and removes it again"
else
  echo "FAIL the via-gateway route was not added then removed"; sed 's/^/     | /' "$STUB_IP_LOG"; fails=$((fails + 1))
fi

printf '%s\n' "$holds" "198.51.100.2:53 open" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "an unpaired row that opens is a failure, not NOT MEASURED" 1 '^FAILED unpaired_dns expected blocked, got open$'

printf '%s\n' "$holds" "198.51.100.2:53 refused" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "an unpaired row that answers with a reset is a failure" 1 '^FAILED unpaired_dns expected blocked, got refused$'

printf '%s\n' "$holds" "192.0.2.1:22 open" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "a paired negative that opens: exit 1 and the row is named" 1 '^FAILED gateway_ssh expected blocked, got open$'

printf '%s\n' "$holds" "198.51.100.1:445 refused" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "a refused connection is not a block" 1 '^FAILED windows_host_smb expected blocked, got refused$'

printf '%s\n' "$holds" "198.51.100.1:445 unreachable" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "no route counts as blocked" 0 '^SUMMARY negatives_blocked=4/4 '

printf '%s\n' "$holds" "198.51.100.1:445 error" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "a name error is not a block" 1 '^FAILED windows_host_smb expected blocked, got error$'

printf '%s\n' "$holds" > "$STUB_TCP_MAP"
STUB_CURL_CODE=offline run --guest lxc --phase baseline
expect "offline guest: exit 1" 1 '^SUMMARY negatives_blocked=4/4 positives_ok=1/1 egress_curl=000$'

printf '%s\n' "" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "a positive that does not open: exit 1" 1 '^FAILED egress_public_https expected open, got dropped$'

printf '%s\n' "$holds" "192.0.2.1:22 open" > "$STUB_TCP_MAP"
run --guest lxc --phase red-first
expect "red-first expects the internal row open and the isolated peer blocked" 0 '^SUMMARY negatives_blocked=3/3 positives_ok=2/2 egress_curl=200$'

printf '%s\n' "$holds" > "$STUB_TCP_MAP"
run --guest lxc --phase red-first
expect "red-first with the firewall still on fails" 1 '^FAILED gateway_ssh expected open, got dropped$'

STUB_UID=1000 run --guest lxc --phase baseline
expect "a via-gateway row without root is a usage error" 2 'tcpvia needs root'

run --guest lxc --phase nonsense
expect "an unknown phase is a usage error" 2 'phase must be one of'

printf '%s\n' "" > "$STUB_TCP_MAP"
sed 's/ channel:[a-z]*$/ True/' "$repo/tests/isolation/targets.example.env" > "$work/example.env"
run --guest vm --phase baseline --targets "$work/example.env"
expect "the committed example file parses" 1 '^FAILED egress_public_https expected open, got dropped$'

sed -i 's/ True$/ -/' "$work/targets.env"
printf '%s\n' "$holds" > "$STUB_TCP_MAP"
run --guest lxc --phase baseline
expect "no paired negative at all: exit 1" 1 'no negative row was measured'

# Real connections: the /dev/tcp outcomes without any stub of the connect itself.
py="$(command -v python3 || command -v python || true)"
if [ -n "$py" ]; then
  "$py" -I -c 'import socket, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(5)
print(s.getsockname()[1], flush=True)
time.sleep(60)' > "$work/port.txt" &
  listener=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$work/port.txt" ] && break; sleep 0.3; done
  open_port="$(head -n1 "$work/port.txt")"
  closed_port="$("$py" -I -c 'import socket
s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  printf '%s\n' "live_listener=all tcp 127.0.0.1 $open_port open open -" \
    "closed_port=all tcp 127.0.0.1 $closed_port blocked blocked -" \
    "listener_as_negative=all tcp 127.0.0.1 $open_port blocked blocked True" > "$work/real.env"
  PATH="$work/bin:$PATH" "$BASH" "$probe" --guest lxc --phase baseline --targets "$work/real.env" > "$work/out.txt" 2>&1 && rc=0 || rc=$?
  expect "real socket: a listener is open" 1 "^PROBE live_listener tcp 127.0.0.1:$open_port open open PASS$"
  expect "real socket: a closed port answers with a reset (refused)" 1 "^PROBE closed_port tcp 127.0.0.1:$closed_port blocked refused FAIL$"
  expect "real socket: an open listener fails a blocked row" 1 "^FAILED listener_as_negative expected blocked, got open$"
else
  echo "skip real-socket cases: no python"
fi

printf '%s\n' "silent=all tcp 192.0.2.1 22 blocked blocked True" > "$work/silent.env"
PATH="$work/fake-bash:$work/bin:$PATH" "$BASH" "$probe" --guest lxc --phase baseline --wait 1 --targets "$work/silent.env" > "$work/out.txt" 2>&1 && rc=0 || rc=$?
expect "real timeout: a silent target is dropped" 0 '^PROBE silent tcp 192.0.2.1:22 blocked dropped PASS$'

[ "$fails" -eq 0 ] && echo "all r15-probe checks passed" || { echo "$fails r15-probe check(s) failed" >&2; exit 1; }
