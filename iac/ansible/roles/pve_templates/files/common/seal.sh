#!/bin/sh
set -eu
umask 077

root="${FINALIZE_ROOT:-}"
login_user="${1:-root}"

case "$login_user" in *[!a-z0-9_-]* | "") echo "SEAL-FAILED: malformed login user"; exit 1 ;; esac
if [ "$login_user" != root ]; then
  for sudoers in "$root"/etc/sudoers.d/*; do
    [ -f "$sudoers" ] || continue
    if grep -Eq "^${login_user}[[:space:]].*NOPASSWD" "$sudoers"; then rm -f "$sudoers"; fi
  done
  [ ! -f "$root/etc/shadow" ] || sed -i "s/^${login_user}:\([^!*]\)/${login_user}:!\1/" "$root/etc/shadow"
  if grep -Eq "^${login_user}:[^!*]" "$root/etc/shadow" 2>/dev/null || grep -Erq "^${login_user}[[:space:]].*NOPASSWD" "$root/etc/sudoers" "$root"/etc/sudoers.d 2>/dev/null; then
    echo "SEAL-FAILED: login user $login_user is not locked or still has NOPASSWD sudo"
    exit 1
  fi
fi

rm -f "$root"/etc/ssh/ssh_host_* "$root/root/.ssh/authorized_keys" "$root"/home/*/.ssh/authorized_keys
: > "$root/etc/machine-id"
[ ! -d "$root/var/lib/dbus" ] || : > "$root/var/lib/dbus/machine-id"
rm -f "$root/var/lib/systemd/random-seed"
rm -rf "$root/var/lib/homelab-build" "$root/tmp/homelab-bundle"

leftover="$(find "$root/etc/ssh" "$root/root" "$root/home" \( -name authorized_keys -o -name 'ssh_host_*' \) -type f 2>/dev/null || true)"
if [ -n "$leftover" ] || [ -s "$root/etc/machine-id" ]; then
  echo "SEAL-FAILED: key material or machine-id left: $leftover"
  exit 1
fi

if [ -z "$root" ]; then
  for unit in ssh.service ssh.socket; do
    systemctl disable "$unit" >/dev/null 2>&1 || true
    case "$(systemctl is-enabled "$unit" 2>/dev/null || true)" in
      enabled | enabled-runtime) echo "SEAL-FAILED: $unit is still enabled"; exit 1 ;;
    esac
  done
fi

echo "SEAL-OK"
