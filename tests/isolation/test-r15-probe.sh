#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
probe="$repo/tests/isolation/r15-probe.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
fails=0

cat > "$work/bin/nc" << 'STUB'
#!/usr/bin/env bash
host="${*: -2:1}"
port="${*: -1}"
state="$(awk -v k="$host:$port" '$1 == k {print $2}' "$STUB_NC_MAP")"
case "${state:-dropped}" in
  open) exit 0 ;;
  refused) echo "nc: connect to $host port $port (tcp) failed: Connection refused" >&2; exit 1 ;;
  unreachable) echo "nc: connect to $host port $port (tcp) failed: Network is unreachable" >&2; exit 1 ;;
  *) echo "nc: connect to $host port $port (tcp) timed out: Operation now in progress" >&2; exit 1 ;;
esac
STUB
cat > "$work/bin/curl" << 'STUB'
#!/usr/bin/env bash
if [ "${STUB_CURL_CODE:-200}" = offline ]; then printf '000'; exit 28; fi
printf '%s' "${STUB_CURL_CODE:-200}"
STUB
chmod +x "$work/bin/nc" "$work/bin/curl"

cat > "$work/targets.env" << 'ROWS'
# label=scope kind host port expect expect_red control
egress_public_https=all tcp 1.1.1.1 443 open open -
gateway_ssh=all tcp 192.0.2.1 22 blocked open True
lxc_to_vm_ssh=lxc tcp 192.0.2.22 22 blocked open True
vm_to_lxc_ssh=vm tcp 192.0.2.21 22 blocked open True
windows_host_smb=all tcp 198.51.100.1 445 blocked blocked True
unpaired_dns=all tcp 198.51.100.2 53 blocked blocked False
ROWS

holds="1.1.1.1:443 open"
export STUB_NC_MAP="$work/nc.map"

run() {
  PATH="$work/bin:$PATH" bash "$probe" --targets "$work/targets.env" "$@" > "$work/out.txt" 2>&1 && rc=0 || rc=$?
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

printf '%s\n' "$holds" > "$STUB_NC_MAP"
run --guest lxc --phase baseline
expect "all hold: exit 0 and the summary" 0 '^SUMMARY negatives_blocked=3/3 positives_ok=1/1 egress_curl=200$'
expect "unpaired row is not measured" 0 '^PROBE unpaired_dns tcp 198.51.100.2:53 blocked dropped NOT MEASURED$'
expect "the other guest's row is skipped" 0 '^PROBE lxc_to_vm_ssh '
grep -q 'vm_to_lxc_ssh' "$work/out.txt" && { echo "FAIL the vm row ran on the lxc guest"; fails=$((fails + 1)); }

printf '%s\n' "$holds" "192.0.2.1:22 open" > "$STUB_NC_MAP"
run --guest lxc --phase baseline
expect "a negative that answers: exit 1 and the row is named" 1 '^FAILED gateway_ssh expected blocked, got open$'

printf '%s\n' "$holds" "198.51.100.1:445 refused" > "$STUB_NC_MAP"
run --guest lxc --phase baseline
expect "a refused connection is not a block" 1 '^FAILED windows_host_smb expected blocked, got refused$'

printf '%s\n' "$holds" > "$STUB_NC_MAP"
STUB_CURL_CODE=offline run --guest lxc --phase baseline
expect "offline guest: exit 1" 1 '^SUMMARY negatives_blocked=3/3 positives_ok=1/1 egress_curl=000$'

printf '%s\n' "" > "$STUB_NC_MAP"
run --guest lxc --phase baseline
expect "a positive that does not open: exit 1" 1 '^FAILED egress_public_https expected open, got dropped$'

printf '%s\n' "$holds" "192.0.2.1:22 open" "192.0.2.22:22 open" > "$STUB_NC_MAP"
run --guest lxc --phase red-first
expect "red-first expects the internal rows open" 0 '^SUMMARY negatives_blocked=1/1 positives_ok=3/3 egress_curl=200$'

printf '%s\n' "$holds" > "$STUB_NC_MAP"
run --guest lxc --phase red-first
expect "red-first with the firewall still on fails" 1 '^FAILED gateway_ssh expected open, got dropped$'

sed -i 's/ True$/ -/' "$work/targets.env"
printf '%s\n' "$holds" > "$STUB_NC_MAP"
run --guest lxc --phase baseline
expect "no paired negative at all: exit 1" 1 'no negative row was measured'

printf '%s
' "" > "$STUB_NC_MAP"
run --guest vm --phase baseline --targets "$repo/tests/isolation/targets.example.env"
expect "the committed example file parses" 1 '^FAILED egress_public_https expected open, got dropped$'

run --guest lxc --phase nonsense
expect "an unknown phase is a usage error" 2 'phase must be one of'

[ "$fails" -eq 0 ] && echo "all r15-probe checks passed" || { echo "$fails r15-probe check(s) failed" >&2; exit 1; }
