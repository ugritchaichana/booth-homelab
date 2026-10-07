#!/bin/sh
set -eu
umask 077

build_id="${1:?usage: finalize.sh <build_id>}"
root="${FINALIZE_ROOT:-}"
out="$root/var/lib/homelab-build"
here="$(cd "$(dirname "$0")" && pwd)"
allowlist="${FINALIZE_ALLOWLIST:-$here/scan-allowlist.txt}"
scan_dirs="${FINALIZE_SCAN_DIRS:-/etc /root /home /opt /srv /var/lib /var/log /usr/local}"

case "$build_id" in *[!A-Za-z0-9._-]* | "") echo "finalize: malformed build id" >&2; exit 2 ;; esac
[ -s "$out/manifest.json" ] || { echo "finalize: no manifest at $out/manifest.json" >&2; exit 1; }
rm -f "$out/pass"

: > "$root/etc/machine-id"
[ ! -d "$root/var/lib/dbus" ] || : > "$root/var/lib/dbus/machine-id"
rm -f "$root/var/lib/systemd/random-seed" "$root/root/.bash_history"
rm -rf "$root"/root/.ansible "$root"/home/*/.ansible "$root"/home/*/.bash_history
rm -rf "$root"/var/log/journal/* "$root"/var/log/cloud-init*.log "$root"/var/log/apt/* "$root"/var/log/auth.log* "$root"/tmp/ansible* 2>/dev/null || true
if [ -z "$root" ] && command -v cloud-init >/dev/null 2>&1; then cloud-init clean --logs --seed >/dev/null 2>&1 || true; fi
if [ -z "$root" ] && command -v apt-get >/dev/null 2>&1; then apt-get clean >/dev/null 2>&1 || true; fi

findings="$(mktemp)"
hits="$(mktemp)"
trap 'rm -f "$findings" "$hits"' EXIT

for dir in $scan_dirs; do
  [ -d "$root$dir" ] || continue
  find "$root$dir" \( -name .credentials -o -name .credentials_rsaparams -o -name .runner \
    -o -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' -o -name .npmrc -o -name NuGet.Config \
    -o -name key.json -o -name random-seed \) -type f -print 2>/dev/null | sed 's/^/forbidden file: /' >> "$findings" || true
  find "$root$dir" -path '*/.docker/config.json' -type f -print 2>/dev/null | sed 's/^/forbidden file: /' >> "$findings" || true
done
if [ -s "$root/etc/machine-id" ]; then echo "machine-id is not empty" >> "$findings"; fi

for dir in $scan_dirs; do
  [ -d "$root$dir" ] || continue
  grep -rIlE --exclude='ssh_host_*' --exclude=authorized_keys -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' -e 'gh[pousr]_[A-Za-z0-9]{36,}' -e 'github_pat_[A-Za-z0-9_]{20,}' -e 'AKIA[0-9A-Z]{16}' "$root$dir" 2>/dev/null >> "$hits" || true
done
while IFS= read -r path; do
  [ -n "$path" ] || continue
  sum="$(sha256sum "$path" | cut -d' ' -f1)"
  if [ -f "$allowlist" ] && grep -q "^${sum}  ${path#"$root"}\$" "$allowlist"; then continue; fi
  echo "secret pattern: ${path#"$root"} sha256=$sum" >> "$findings"
done < "$hits"

if [ -s "$findings" ]; then
  echo "finalize: SCAN FAILED, no pass marker written" >&2
  sed 's/^/finalize:   /' "$findings" >&2
  exit 1
fi

sync
printf 'PASS %s\n' "$build_id" > "$out/pass"
echo "finalize: cleanup and scan passed for $build_id"
