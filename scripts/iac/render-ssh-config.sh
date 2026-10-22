#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
inventory="${HOMELAB_INVENTORY:-$repo/iac/inventory/hosts.yml}"
out="${HOMELAB_CONFIG_DIR:-$HOME/.config/homelab}"
winssh="${HOMELAB_WINSSH:-/mnt/c/Windows/System32/OpenSSH/ssh.exe}"
cmdexe="${HOMELAB_CMDEXE:-/mnt/c/Windows/System32/cmd.exe}"

die() { echo "ERROR: $*" >&2; exit 1; }
winvar() { (cd /mnt/c 2>/dev/null || :; "$cmdexe" /c "echo %$1%" 2>/dev/null | tr -d '\r'); }

[ -x "$winssh" ] || die "Windows OpenSSH client not found at $winssh"
command -v sops >/dev/null || die "sops not installed (scripts/bootstrap/operator-toolchain.sh)"

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
  appdata="$(winvar APPDATA)"
  [ -n "$appdata" ] && SOPS_AGE_KEY_FILE="$(wslpath -u "$appdata")/sops/age/keys.txt" && export SOPS_AGE_KEY_FILE
fi

winhome="$(winvar USERPROFILE)"
[ -n "$winhome" ] || die "cannot resolve the Windows profile directory"
winhome="$(printf '%s' "$winhome" | tr '\\' '/')"
safe_path='^[A-Za-z0-9:/._ -]+$'
[[ "$winhome" =~ $safe_path ]] || die "unsafe characters in the Windows profile path"

umask 077
mkdir -p "$out"
cfg="$(mktemp "$out/ssh_config.XXXXXX")"
kh="$(mktemp "$out/known_hosts.XXXXXX")"
trap 'rm -f "$cfg" "$kh"' EXIT

py_out="$(python3 - "$inventory" <<'PY'
import ipaddress, re, sys, yaml
inv = yaml.safe_load(open(sys.argv[1]))
seen = {}
def walk(node):
    for name, hv in (node.get("hosts") or {}).items():
        seen[name] = hv or {}
    for child in (node.get("children") or {}).values():
        walk(child)
walk(inv["all"])
def need(value, pattern, what, name):
    if not isinstance(value, str) or not re.fullmatch(pattern, value):
        sys.exit(f"invalid {what} for host {name!r}")
    return value
rows = []
for name, hv in sorted(seen.items()):
    need(name, r"[a-z0-9][a-z0-9-]{0,62}", "host name", name)
    addr = str(ipaddress.ip_address(hv["ansible_host"]))
    user = need(hv.get("ansible_user", "root"), r"[a-z_][a-z0-9_-]{0,31}", "ansible_user", name)
    key = need(hv["ssh_key_name"], r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", "ssh_key_name", name)
    rows.append("\t".join([name, addr, user, key]))
print(len(seen))
print("\n".join(rows))
PY
)" || die "cannot parse $inventory"
mapfile -t py_lines <<<"$py_out"
expected="${py_lines[0]}"
rows=("${py_lines[@]:1}")
[ "$expected" -gt 0 ] || die "no hosts in $inventory"
[ "${#rows[@]}" -eq "$expected" ] || die "parsed ${#rows[@]} of $expected hosts"

for row in "${rows[@]}"; do
  IFS=$'\t' read -r name addr user key <<<"$row"
  secret="iac/secrets/hosts/${name}-ssh.sops.yaml"
  pub="$(cd "$repo" && sops -d --extract '["ssh_host_ed25519_public"]' "$secret")" || die "cannot decrypt $secret"
  read -r keytype keydata _ <<<"$pub"
  [ "$keytype" = "ssh-ed25519" ] && [ -n "$keydata" ] || die "$secret does not hold an ssh-ed25519 public key"
  printf '%s %s %s\n' "$name" "$keytype" "$keydata" >> "$kh"
  cat >> "$cfg" <<CFG
Host $name $addr
  HostName $addr
  HostKeyAlias $name
  User $user
  IdentityFile ~/.ssh/$key
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  CheckHostIP no
  UserKnownHostsFile "$out/known_hosts"
  ServerAliveInterval 15
  ServerAliveCountMax 8
  ProxyCommand $winssh -i "$winhome/.ssh/$key" -o BatchMode=yes -W %h:%p root@$addr

CFG
done

# the secret path is stable on purpose: an alias rename does not change the pinned key
cache_jump="pve01"
rendered_extra=0
render_extra() {
  local group="$1" file="$2" endpoint="$3" secret="$4" row alias addr user key pub keytype keydata
  if [ ! -f "$repo/$secret" ]; then
    echo "note: the $group host is not rendered; $secret does not exist yet (capture its host key after the first apply)" >&2
    return 0
  fi
  row="$(python3 - "$inventory" "$file" "$cache_jump" "$group" "$endpoint" <<'PY'
import ipaddress, re, sys, yaml
hosts = yaml.safe_load(open(sys.argv[1]))["all"]["children"]["pve_hosts"]["hosts"]
group_hosts = yaml.safe_load(open(sys.argv[2]))["all"]["children"][sys.argv[4]]["hosts"]
if len(group_hosts) != 1:
    sys.exit("the %s group must hold exactly one host" % sys.argv[4])
alias, extra = next(iter(group_hosts.items()))
if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", alias):
    sys.exit("invalid host alias")
addr = str(ipaddress.ip_address(hosts[sys.argv[3]][sys.argv[5]]["address"]))
user = extra["ansible_user"]
key = extra["ssh_key_name"]
for value, pattern in ((user, r"[a-z_][a-z0-9_-]{0,31}"), (key, r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")):
    if not re.fullmatch(pattern, value):
        sys.exit("invalid host value")
print("	".join([alias, addr, user, key]))
PY
)" || die "cannot read the $group host from $file and $endpoint of $cache_jump in $inventory"
  IFS=$'	' read -r alias addr user key <<<"$row"
  pub="$(cd "$repo" && sops -d --extract '["ssh_host_ed25519_public"]' "$secret")" || die "cannot decrypt $secret"
  read -r keytype keydata _ <<<"$pub"
  [ "$keytype" = "ssh-ed25519" ] && [ -n "$keydata" ] || die "$secret does not hold an ssh-ed25519 public key"
  printf '%s %s %s
' "$alias" "$keytype" "$keydata" >> "$kh"
  cat >> "$cfg" <<CFG
Host $alias $addr
  HostName $addr
  HostKeyAlias $alias
  User $user
  IdentityFile ~/.ssh/$key
  IdentitiesOnly yes
  StrictHostKeyChecking yes
  CheckHostIP no
  UserKnownHostsFile "$out/known_hosts"
  ProxyJump $cache_jump

CFG
  rendered_extra=$((rendered_extra + 1))
}
render_extra cache "$repo/iac/inventory/cache.yml" cache_endpoint iac/secrets/hosts/cache01-ssh.sops.yaml
render_extra sim_cache "$repo/iac/inventory/sim-cache.yml" sim_cache_endpoint iac/secrets/hosts/simcache-ssh.sops.yaml

cat >> "$cfg" <<CFG
Host *
  StrictHostKeyChecking yes
  UserKnownHostsFile "$out/known_hosts"
  GlobalKnownHostsFile /dev/null
CFG

mv "$cfg" "$out/ssh_config"
mv "$kh" "$out/known_hosts"
trap - EXIT
echo "rendered $((${#rows[@]} + rendered_extra)) host(s) into $out"
