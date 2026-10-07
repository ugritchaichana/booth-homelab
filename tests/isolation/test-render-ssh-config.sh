#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

mkdir -p "$work/bin" "$work/repo/scripts/iac" "$work/repo/iac/inventory" "$work/repo/iac/secrets/hosts"
cp "$repo/scripts/iac/render-ssh-config.sh" "$work/repo/scripts/iac/"
cp "$repo/iac/inventory/hosts.yml" "$repo/iac/inventory/cache.yml" "$work/repo/iac/inventory/"
touch "$work/repo/iac/secrets/hosts/pve01-ssh.sops.yaml" "$work/repo/iac/secrets/hosts/cache01-ssh.sops.yaml"
printf '#!/bin/sh\necho "ssh-ed25519 AAAAFAKEKEYDATA stub"\n' > "$work/bin/sops"
cat > "$work/bin/cmd.exe" << 'STUB'
#!/bin/sh
case "$*" in
  *USERPROFILE*) echo "C:/Users/fake" ;;
  *) echo ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$work/bin/ssh.exe"
chmod +x "$work/bin/sops" "$work/bin/cmd.exe" "$work/bin/ssh.exe"

render() {
  PATH="$work/bin:$PATH" HOMELAB_CMDEXE="$work/bin/cmd.exe" HOMELAB_WINSSH="$work/bin/ssh.exe" SOPS_AGE_KEY_FILE="$work/age.key" HOMELAB_CONFIG_DIR="$work/out" bash "$work/repo/scripts/iac/render-ssh-config.sh" 2>&1
}

check() {
  if ! grep -q -- "$2" "$work/out/$1"; then echo "FAIL: $1 lacks: $2" >&2; fails=$((fails + 1)); fi
}

verdict() {
  if [ "$fails" -eq "$before" ]; then echo "ok: $1"; fi
}

before=$fails
render > "$work/render.log" || { cat "$work/render.log" >&2; echo "FAIL: render failed" >&2; exit 1; }
check ssh_config "^Host build-cache 10.99.17.10$"
check ssh_config "^  HostKeyAlias build-cache$"
check ssh_config "^  StrictHostKeyChecking yes$"
check known_hosts "^build-cache ssh-ed25519 AAAAFAKEKEYDATA$"
if grep -q "cache01" "$work/out/ssh_config" "$work/out/known_hosts"; then echo "FAIL: the old alias is still rendered" >&2; fails=$((fails + 1)); fi
alias_line="$(grep -c "^Host build-cache " "$work/out/ssh_config")"
hka_name="$(awk '/^Host build-cache /{f=1} f && /HostKeyAlias/{print $2; exit}' "$work/out/ssh_config")"
kh_name="$(awk '$1 == "build-cache" {print $1}' "$work/out/known_hosts")"
if [ "$alias_line" != 1 ] || [ "$hka_name" != "$kh_name" ]; then echo "FAIL: HostKeyAlias '$hka_name' does not match the known_hosts name '$kh_name'" >&2; fails=$((fails + 1)); fi
verdict "alias, HostKeyAlias and the known_hosts name agree"

before=$fails
sed -i 's/build-cache:/renamed-cache:/' "$work/repo/iac/inventory/cache.yml"
render > "$work/render2.log" || { cat "$work/render2.log" >&2; echo "FAIL: render after the inventory rename failed" >&2; exit 1; }
check ssh_config "^Host renamed-cache 10.99.17.10$"
check known_hosts "^renamed-cache ssh-ed25519 AAAAFAKEKEYDATA$"
verdict "the rendered alias follows the inventory, the key file path does not move"

printf '        second-cache:\n          ansible_host: 10.99.17.11\n          ansible_user: root\n          ssh_key_name: k\n' >> "$work/repo/iac/inventory/cache.yml"
if render > "$work/render3.log"; then echo "FAIL: two cache hosts were accepted" >&2; fails=$((fails + 1)); else echo "ok: two cache hosts are rejected"; fi

[ "$fails" -eq 0 ] || { echo "FAIL: $fails check(s) failed" >&2; exit 1; }
echo "PASS"
