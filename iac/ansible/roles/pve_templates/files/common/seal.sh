#!/bin/sh
set -eu
umask 077

root="${FINALIZE_ROOT:-}"

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
