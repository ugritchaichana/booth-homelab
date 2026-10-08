#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${LAB_ACCOUNT_SCRIPT:-$repo/scripts/iac/lab-account-apply.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
[ -f "$script" ] || { echo "ERROR: no script at $script" >&2; exit 2; }

mkdir -p "$work/bin"
cat > "$work/bin/getent" <<'SH'
#!/usr/bin/env bash
grep "^$2:" "$STUB_DIR/shadow" || exit 2
SH
cat > "$work/bin/chpasswd" <<'SH'
#!/usr/bin/env bash
echo "chpasswd $*" >> "$STUB_DIR/argv.log"
while IFS=: read -r user password; do
  hash="$(printf '%s' "$password" | perl -e 'chomp(my $p = <STDIN>); print crypt($p, q($6$stubsalt$))')"
  grep -v "^$user:" "$STUB_DIR/shadow" > "$STUB_DIR/shadow.new" || true
  echo "$user:$hash:" >> "$STUB_DIR/shadow.new"
  mv "$STUB_DIR/shadow.new" "$STUB_DIR/shadow"
done
SH
cat > "$work/bin/useradd" <<'SH'
#!/usr/bin/env bash
echo "useradd $*" >> "$STUB_DIR/argv.log"
echo guest >> "$STUB_DIR/users"
echo "guest:!:" >> "$STUB_DIR/shadow"
: > "$STUB_DIR/groups"
SH
cat > "$work/bin/id" <<'SH'
#!/usr/bin/env bash
if [ "$1" = -nG ]; then echo "guest $(cat "$STUB_DIR/groups" 2>/dev/null)"; exit 0; fi
grep -qx "$1" "$STUB_DIR/users" 2>/dev/null
SH
cat > "$work/bin/gpasswd" <<'SH'
#!/usr/bin/env bash
echo "gpasswd $*" >> "$STUB_DIR/argv.log"
tr ' ' '\n' < "$STUB_DIR/groups" | grep -vx "$3" | tr '\n' ' ' > "$STUB_DIR/groups.new"
mv "$STUB_DIR/groups.new" "$STUB_DIR/groups"
SH
chmod +x "$work/bin/"*

ROOT_PW='root-pass-value'
GUEST_PW='guest-pass-value'
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

fresh() {
  export STUB_DIR="$work/case-$1"
  rm -rf "$STUB_DIR"; mkdir -p "$STUB_DIR"
  echo "root:!:" > "$STUB_DIR/shadow"
  : > "$STUB_DIR/argv.log"
}
run() { printf '%s\n%s\n' "$1" "$2" | PATH="$work/bin:$PATH" bash "$script" "${@:3}" > "$STUB_DIR/out" 2>&1; }

fresh first
run "$ROOT_PW" "$GUEST_PW" && rc=0 || rc=$?
grep -qx 'root-password: changed' "$STUB_DIR/out" && grep -qx 'guest-user: created' "$STUB_DIR/out" \
  && grep -qx 'guest-password: changed' "$STUB_DIR/out" && grep -qx 'changed=3' "$STUB_DIR/out" && [ "$rc" -eq 0 ] \
  && pass "a locked root and a missing guest are set up" || fail "first run" "$(tr '\n' '|' < "$STUB_DIR/out")"

run "$ROOT_PW" "$GUEST_PW"
before="$(grep -c '^chpasswd' "$STUB_DIR/argv.log")"
grep -qx 'changed=0' "$STUB_DIR/out" && [ "$before" -eq 2 ] \
  && pass "a second run with the same passwords changes nothing" || fail "second run" "$(tr '\n' '|' < "$STUB_DIR/out")"

run "$ROOT_PW" "other-guest-value"
grep -qx 'root-password: ok' "$STUB_DIR/out" && grep -qx 'guest-password: changed' "$STUB_DIR/out" && grep -qx 'changed=1' "$STUB_DIR/out" \
  && pass "a new guest password replaces the old one and leaves root alone" || fail "guest rotation" "$(tr '\n' '|' < "$STUB_DIR/out")"

fresh groups
echo guest > "$STUB_DIR/users"
echo "guest:!:" >> "$STUB_DIR/shadow"
echo "users sudo docker" > "$STUB_DIR/groups"
run "$ROOT_PW" "$GUEST_PW"
grep -qx 'guest-group: removed sudo' "$STUB_DIR/out" && grep -qx 'guest-group: removed docker' "$STUB_DIR/out" \
  && ! grep -q 'removed users' "$STUB_DIR/out" && grep -qw users "$STUB_DIR/groups" \
  && pass "guest leaves sudo and docker and keeps an ordinary group" || fail "groups" "$(tr '\n' '|' < "$STUB_DIR/out")"

fresh empty
run "$ROOT_PW" "" && rc=0 || rc=$?
[ "$rc" -eq 2 ] && ! grep -q chpasswd "$STUB_DIR/argv.log" \
  && pass "an empty guest password is refused before anything changes" || fail "empty guest" "rc=$rc"

fresh emptyroot
run "" "$GUEST_PW" && rc=0 || rc=$?
[ "$rc" -eq 2 ] && ! grep -q chpasswd "$STUB_DIR/argv.log" \
  && pass "an empty root password is refused before anything changes" || fail "empty root" "rc=$rc"

fresh rootonly
run "$ROOT_PW" "" --root-only && rc=0 || rc=$?
[ "$rc" -eq 0 ] && grep -qx 'changed=1' "$STUB_DIR/out" && ! grep -q useradd "$STUB_DIR/argv.log" \
  && pass "--root-only sets root and creates no guest" || fail "root-only" "rc=$rc $(tr '\n' '|' < "$STUB_DIR/out")"

fresh argv
run "$ROOT_PW" "$GUEST_PW"
! grep -qE "$ROOT_PW|$GUEST_PW" "$STUB_DIR/argv.log" && ! grep -qE "$ROOT_PW|$GUEST_PW" "$STUB_DIR/out" \
  && pass "no password reaches a command line or the output" || fail "argv" "a password leaked"

fresh badflag
run "$ROOT_PW" "$GUEST_PW" --other && rc=0 || rc=$?
[ "$rc" -eq 2 ] && pass "an unknown option is refused" || fail "unknown option" "rc=$rc"

[ "$fails" -eq 0 ] || { echo "$fails failure(s)"; exit 1; }
echo "all lab account cases passed"
