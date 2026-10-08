#!/usr/bin/env bash
set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 2; }
usage() {
  cat >&2 <<'TXT'
usage: lab-account-apply.sh [--root-only]
  Run as root on one machine. Reads two lines on stdin: the root password, then the guest password.
  Sets root's password and keeps a local user `guest` with the guest password and no administrative group.
  --root-only sets root only (the Proxmox host, whose visitor account is guest@pve).
  Prints one line per item and `changed=<n>`; a second run with the same input prints changed=0.
TXT
  exit 2
}

root_only=0
case "${1:-}" in
  "") ;;
  --root-only) root_only=1 ;;
  *) usage ;;
esac

IFS= read -r root_password || true
IFS= read -r guest_password || true
[ -n "$root_password" ] || die "the root password on stdin is empty"
[ "$root_only" -eq 1 ] || [ -n "$guest_password" ] || die "the guest password on stdin is empty"

privileged_groups="sudo wheel adm docker lxd disk"
changed=0

matches() {
  local hash
  hash="$(getent shadow "$1" | cut -d: -f2)"
  case "$hash" in '$'*) ;; *) return 1 ;; esac
  [ "$(printf '%s\n%s\n' "$2" "$hash" | perl -e 'chomp(my $p = <STDIN>); chomp(my $h = <STDIN>); print crypt($p, $h) eq $h ? "yes" : "no"')" = yes ]
}

set_password() {
  if matches "$1" "$2"; then
    echo "$1-password: ok"
  else
    printf '%s:%s\n' "$1" "$2" | chpasswd
    echo "$1-password: changed"
    changed=$((changed + 1))
  fi
}

set_password root "$root_password"

if [ "$root_only" -eq 0 ]; then
  if id guest >/dev/null 2>&1; then
    echo "guest-user: ok"
  else
    useradd --create-home --shell /bin/bash guest
    echo "guest-user: created"
    changed=$((changed + 1))
  fi
  for group in $(id -nG guest); do
    case " $privileged_groups " in
      *" $group "*) gpasswd -d guest "$group" >/dev/null; echo "guest-group: removed $group"; changed=$((changed + 1)) ;;
    esac
  done
  set_password guest "$guest_password"
fi

echo "changed=$changed"
