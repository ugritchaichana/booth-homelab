#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${CACHE_WRITER_SECRET_SCRIPT:-$repo/scripts/iac/cache-writer-secret.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

[ -f "$script" ] || { echo "ERROR: no script at $script" >&2; exit 2; }

mkdir -p "$work/bin"
cat > "$work/bin/sops" <<'SH'
#!/usr/bin/env bash
echo "sops $*" >> "$STUB_DIR/argv.log"
case "$1" in
  decrypt) [ -s "$STUB_DIR/store" ] || exit 1; cat "$STUB_DIR/store" ;;
  encrypt)
    out=""
    while [ "$#" -gt 0 ]; do [ "$1" = "--output" ] && out="$2"; shift; done
    cat > /dev/null
    : > "$out" ;;
  set) cat > "$STUB_DIR/store.json"; sed -e 's/^"//' -e 's/"$//' "$STUB_DIR/store.json" > "$STUB_DIR/store" ;;
  *) exit 2 ;;
esac
SH
cat > "$work/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "gh $*" >> "$STUB_DIR/argv.log"
case "$1 $2" in
  "repo view") echo "example/repo" ;;
  "secret set")
    body=""
    while [ "$#" -gt 0 ]; do [ "$1" = "--body" ] && body="$2"; shift; done
    if [ -n "$body" ]; then printf '%s' "$body" > "$STUB_DIR/gh_body"; else cat > "$STUB_DIR/gh_body"; fi ;;
  *) exit 2 ;;
esac
SH
chmod +x "$work/bin/sops" "$work/bin/gh"

unset GITHUB_REPOSITORY GH_REPO GH_TOKEN GITHUB_TOKEN
export STUB_DIR="$work" PATH="$work/bin:$PATH" SOPS_AGE_KEY_FILE=/nonexistent-age-key
export CACHE_WRITER_SECRET_FILE="$work/secrets/pve01-cache.sops.yaml"

reset() { rm -rf "$work/argv.log" "$work/store" "$work/store.json" "$work/gh_body" "$work/secrets"; : > "$work/argv.log"; }

assert_run() {
  local label="$1" out="$work/out.log" body stored
  shift
  "$@" > "$out" 2>&1 < /dev/null || { cat "$out" >&2; echo "FAIL: $label: the script exited non-zero" >&2; return 1; }
  [ -s "$work/gh_body" ] || { echo "FAIL: $label: no secret reached gh" >&2; return 1; }
  body="$(cat "$work/gh_body")"
  stored="$(cat "$work/store")"
  [ "${#body}" -ge 40 ] || { echo "FAIL: $label: the password has ${#body} characters, want at least 40" >&2; return 1; }
  if grep -qF -- "$body" "$work/argv.log"; then echo "FAIL: $label: the password is on a command line" >&2; return 1; fi
  [ "$body" = "$stored" ] || { echo "FAIL: $label: the SOPS value and the GitHub value differ" >&2; return 1; }
  if grep -qF -- "$body" "$out"; then echo "FAIL: $label: the password was printed" >&2; return 1; fi
  grep -qF "gh secret set CACHE_WRITER_PASSWORD --env cache-writer --repo example/repo" "$work/argv.log" || { echo "FAIL: $label: unexpected gh arguments" >&2; return 1; }
  grep -qF "sops set --value-stdin" "$work/argv.log" || { echo "FAIL: $label: the value did not go through --value-stdin" >&2; return 1; }
  grep -qF "CACHE_WRITER_PASSWORD" "$out" || { echo "FAIL: $label: the secret name was not reported" >&2; return 1; }
}

reset
assert_run "first run" bash "$script"
first="$(cat "$work/gh_body")"
echo "ok: first run stores a ${#first}-character password through stdin, nothing on argv or in the output"

writes() { grep -cE "^(sops set|sops encrypt|gh secret)" "$work/argv.log" || true; }
calls_before="$(writes)"
bash "$script" > "$work/out.log" 2>&1
[ "$(writes)" -eq "$calls_before" ] || { echo "FAIL: a second run without --rotate changed the secret" >&2; exit 1; }
[ "$(cat "$work/gh_body")" = "$first" ] || { echo "FAIL: a second run without --rotate replaced the secret" >&2; exit 1; }
echo "ok: a second run without --rotate only reads the SOPS key"

assert_run "rotate" bash "$script" --rotate
[ "$(cat "$work/gh_body")" != "$first" ] || { echo "FAIL: --rotate kept the old password" >&2; exit 1; }
echo "ok: --rotate replaces the password"

mutate() {
  local label="$1" expr="$2" copy="$work/mut"
  rm -rf "$copy"
  mkdir -p "$copy/scripts/iac"
  cp "$script" "$copy/scripts/iac/cache-writer-secret.sh"
  sed -i -e "$expr" "$copy/scripts/iac/cache-writer-secret.sh"
  if cmp -s "$script" "$copy/scripts/iac/cache-writer-secret.sh"; then
    echo "FAIL: mutation '$label' changed nothing" >&2
    exit 1
  fi
  reset
  if assert_run "$label" bash "$copy/scripts/iac/cache-writer-secret.sh" > "$work/mut.log" 2>&1; then
    echo "FAIL: mutation '$label' was not caught" >&2
    exit 1
  fi
  echo "ok: mutation '$label' is rejected: $(head -n1 "$work/mut.log")"
}

mutate "password on the gh command line" 's@printf .%s. "\$password" | gh secret set "\$secret_name"@gh secret set "$secret_name" --body "$password"@'
mutate "password on the sops command line" 's@^printf .*"\$password" | sops set --value-stdin "\$secret_file"@sops set --value-stdin "$secret_file" "$password"@'
mutate "password echoed" 's|^\[ "\${#password}" -ge|echo "$password"; [ "${#password}" -ge|'
mutate "short password" 's/cut -c1-48/cut -c1-12/; s/^min_length=40/min_length=1/'
