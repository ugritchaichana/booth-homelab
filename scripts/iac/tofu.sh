#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
conf="${HOMELAB_CONFIG_DIR:-$HOME/.config/homelab}"
state_root="${HOMELAB_STATE_ROOT:-/var/lib/homelab/tofu}"
inventory="$repo/iac/inventory/hosts.yml"
cmdexe="/mnt/c/Windows/System32/cmd.exe"
local_port=18006
safe_path='^/[A-Za-z0-9._/ -]+$'
name_re='^[a-z0-9][a-z0-9-]{0,62}$'
tmp=""

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 is not installed (scripts/bootstrap/operator-toolchain.sh)"; }
winvar() { (cd /mnt/c && "$cmdexe" /c "echo %$1%" 2>/dev/null | tr -d '\r'); }

[ "$#" -ge 3 ] || { echo "usage: tofu.sh <stack> <host> init-passphrase [--rotate] | <tofu args>" >&2; exit 2; }
stack="$1"; host="$2"; shift 2

[[ "$stack" =~ $name_re ]] || die "invalid stack name"
[[ "$host" =~ $name_re ]] || die "invalid host name"
stackdir="$repo/iac/tofu/stacks/$stack"
[ -d "$stackdir" ] || die "no stack at iac/tofu/stacks/$stack"
[[ "$state_root" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "unsafe HOMELAB_STATE_ROOT"
case "$state_root" in /mnt/*) die "state must live on the WSL ext4 filesystem, not under /mnt" ;; esac

need sops
need python3
python3 - "$inventory" "$host" <<'PY' || die "host $host is not a pve_hosts entry in iac/inventory/hosts.yml"
import sys, yaml
inv = yaml.safe_load(open(sys.argv[1]))
sys.exit(0 if sys.argv[2] in inv["all"]["children"]["pve_hosts"]["hosts"] else 1)
PY

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ ! -f "$HOME/.config/sops/age/keys.txt" ] && [ -x "$cmdexe" ]; then
  appdata="$(winvar APPDATA)"
  [ -n "$appdata" ] && SOPS_AGE_KEY_FILE="$(wslpath -u "$appdata")/sops/age/keys.txt" && export SOPS_AGE_KEY_FILE
fi

state_secret="iac/secrets/tofu/$host-state.sops.yaml"
api_secret="iac/secrets/tofu/$host-api.sops.yaml"
state="$state_root/$stack/$host.tfstate"

init_passphrase() {
  local rotate=0 len
  case "${1:-}" in
    "") ;;
    --rotate) rotate=1 ;;
    *) die "usage: tofu.sh $stack $host init-passphrase [--rotate]" ;;
  esac
  cd "$repo"
  if [ -f "$state_secret" ]; then
    len="$(sops decrypt --extract '["state_passphrase"]' "$state_secret" 2>/dev/null | wc -c)" \
      || die "$state_secret exists but cannot be decrypted; fix the age key or remove the file by hand"
    if [ "$len" -gt 0 ] && [ "$rotate" -eq 0 ]; then
      die "$state_secret already holds a passphrase; --rotate replaces it"
    fi
    if [ -e "$state" ]; then
      die "$state is encrypted with the current passphrase; move it aside before --rotate"
    fi
  fi
  umask 077
  mkdir -p "$(dirname "$state_secret")"
  tmp="$(mktemp "$(dirname "$state_secret")/.$host-state.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  { printf '{"state_passphrase":"'; head -c 48 /dev/urandom | base64 -w0; printf '"}'; } \
    | sops encrypt --filename-override "$state_secret" --input-type json --output-type yaml --output "$tmp" /dev/stdin
  len="$(sops decrypt --input-type yaml --extract '["state_passphrase"]' "$tmp" | wc -c)"
  [ "$len" -ge 64 ] || die "the stored passphrase is shorter than expected ($len characters)"
  mv -f "$tmp" "$state_secret"
  trap - EXIT
  echo "wrote a 48-byte random passphrase (base64, $len characters) to $state_secret"
}

if [ "$1" = "init-passphrase" ]; then
  shift
  init_passphrase "$@"
  exit 0
fi

need ssh
need flock
need jq
need tofu
[ -f "$conf/ssh_config" ] || "$repo/scripts/iac/render-ssh-config.sh"

umask 077
install -d -m 0700 "$state_root/$stack" 2>/dev/null \
  || die "cannot create $state_root/$stack; create the root once: sudo install -d -o \"\$USER\" -m 0700 $state_root"

backup_state() {
  [ -s "$state" ] || return 0
  jq -e 'has("encrypted_data")' "$state" >/dev/null || die "refusing to copy $state: it is not encrypted"
  local base dest latest
  base="$(winvar LOCALAPPDATA)"
  [ -n "$base" ] || die "cannot resolve the Windows local application data directory"
  base="$(wslpath -u "$base")" || die "cannot convert the Windows local application data path"
  [[ "$base" =~ $safe_path ]] || die "unsafe characters in the Windows local application data path"
  dest="$base/homelab/tofu-state"
  mkdir -p "$dest"
  latest="$(ls -1t "$dest/$stack-$host-"*.tfstate 2>/dev/null | head -n1 || true)"
  if [ -n "$latest" ] && cmp -s "$state" "$latest"; then return 0; fi
  cp "$state" "$dest/$stack-$host-$(date -u +%Y%m%dT%H%M%SZ).tfstate"
  echo "state copy: $dest"
}

run="$conf/run"
sock="$run/tofu-$host.sock"
forward_open=0
sshopts=(-F "$conf/ssh_config" -o "ControlPath=$sock")

open_forward() {
  install -d -m 0700 "$run"
  exec 8>"$run/tofu-users.lock"
  flock -s 8
  exec 9>"$run/tofu-setup.lock"
  flock -x 9
  if ! ssh "${sshopts[@]}" -O check "$host" 2>/dev/null; then
    rm -f "$sock"
    ssh "${sshopts[@]}" -o BatchMode=yes -o ControlMaster=yes -o ExitOnForwardFailure=yes \
      -N -f -L "127.0.0.1:$local_port:127.0.0.1:8006" "$host" 8>&- 9>&- \
      || die "cannot open the forward to $host (is another host's forward holding port $local_port?)"
  fi
  forward_open=1
  exec 9>&-
}

close_forward() {
  [ "$forward_open" -eq 1 ] || return 0
  forward_open=0
  exec 9>"$run/tofu-setup.lock"
  flock -x 9
  exec 8>&-
  exec 7>"$run/tofu-users.lock"
  if flock -n -x 7; then ssh "${sshopts[@]}" -O exit "$host" 7>&- 9>&- 2>/dev/null || true; fi
  exec 7>&- 9>&-
}

case "$1" in
  plan|apply|destroy|refresh|import|console) needs_api=1 ;;
  *) needs_api=0 ;;
esac
case "$1" in
  apply|destroy|import|taint|untaint) backup_state ;;
  state) case "${2:-}" in mv|rm|push|replace-provider) backup_state ;; esac ;;
esac

passphrase="$(cd "$repo" && sops decrypt --extract '["state_passphrase"]' "$state_secret")" \
  || die "cannot read $state_secret (run: tofu.sh $stack $host init-passphrase)"
[ "${#passphrase}" -ge 32 ] || die "$state_secret holds a passphrase shorter than 32 characters"

token=""
if [ "$needs_api" -eq 1 ]; then
  token_id="$(cd "$repo" && sops decrypt --extract '["token_id"]' "$api_secret")" || die "cannot read $api_secret"
  token_secret="$(cd "$repo" && sops decrypt --extract '["token_secret"]' "$api_secret")" || die "cannot read $api_secret"
  [[ "$token_id" =~ ^[a-z0-9._-]+@[a-z]+![A-Za-z0-9._-]+$ ]] || die "$api_secret holds a malformed token_id"
  [ -n "$token_secret" ] || die "$api_secret holds no token_secret"
  token="$token_id=$token_secret"
  trap close_forward EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  open_forward
fi

unset PROXMOX_VE_ENDPOINT PROXMOX_VE_USERNAME PROXMOX_VE_PASSWORD PROXMOX_VE_API_TOKEN \
  PROXMOX_VE_AUTH_TICKET PROXMOX_VE_CSRF_PREVENTION_TOKEN TF_VAR_state_passphrase
export TF_DATA_DIR="$state_root/$stack/$host.data"
export TF_VAR_host="$host"
export TF_CLI_ARGS_init="-backend-config=path=$state"

rc=0
(
  export TF_VAR_state_passphrase="$passphrase"
  [ -z "$token" ] || export PROXMOX_VE_API_TOKEN="$token"
  exec tofu -chdir="$stackdir" "$@"
) || rc=$?
exit "$rc"
