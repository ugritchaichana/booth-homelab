#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage: build-auto-install-iso.sh --source-iso FILE --pubkey-operator FILE --pubkey-automation FILE --output FILE [options]

  --source-iso FILE        stock installer ISO            (env PVE_SOURCE_ISO)
  --pubkey-operator FILE   operator SSH public key        (env PVE_PUBKEY_OPERATOR)
  --pubkey-automation FILE automation SSH public key      (env PVE_PUBKEY_AUTOMATION)
  --output FILE            prepared ISO to create         (env PVE_OUTPUT_ISO)
  --sops-file FILE         default iac/secrets/hosts/pve01.sops.yaml
  --template FILE          default iac/proxmox/answer.pve01.toml.tmpl
  --psd1 FILE              default scripts/hyperv/pve01.psd1 (MAC, guest and gateway address)
  --force                  overwrite an existing output

SOPS_AGE_KEY_FILE must point at the age identity able to decrypt the sops file.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
src="${PVE_SOURCE_ISO:-}"
pub_op="${PVE_PUBKEY_OPERATOR:-}"
pub_auto="${PVE_PUBKEY_AUTOMATION:-}"
out="${PVE_OUTPUT_ISO:-}"
sops_file="$repo/iac/secrets/hosts/pve01.sops.yaml"
tmpl="$repo/iac/proxmox/answer.pve01.toml.tmpl"
psd1="$repo/scripts/hyperv/pve01.psd1"
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --source-iso) src="${2:?}"; shift 2 ;;
    --pubkey-operator) pub_op="${2:?}"; shift 2 ;;
    --pubkey-automation) pub_auto="${2:?}"; shift 2 ;;
    --output) out="${2:?}"; shift 2 ;;
    --sops-file) sops_file="${2:?}"; shift 2 ;;
    --template) tmpl="${2:?}"; shift 2 ;;
    --psd1) psd1="${2:?}"; shift 2 ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

for v in src pub_op pub_auto out; do
  [ -n "${!v}" ] || { usage >&2; die "missing --${v//_/-} (or its env variable)"; }
done
for f in "$src" "$pub_op" "$pub_auto" "$sops_file" "$tmpl" "$psd1"; do
  [ -f "$f" ] || die "not a file: $f"
done
for t in sops openssl python3 proxmox-auto-install-assistant shred; do
  command -v "$t" >/dev/null || die "missing tool: $t"
done
[ -n "${SOPS_AGE_KEY_FILE:-}" ] && [ -f "$SOPS_AGE_KEY_FILE" ] || die "SOPS_AGE_KEY_FILE must name the age identity file"
if [ -e "$out" ] && [ "$force" -ne 1 ]; then
  die "output exists: $out (use --force)"
fi

psd1_value() { awk -F"'" -v k="$1" '$0 ~ "^[[:space:]]*" k "[[:space:]]*=" {print $2; exit}' "$psd1"; }

mac="$(psd1_value MacAddress)"
guest="$(psd1_value GuestAddress)"
gateway="$(psd1_value HostAddress)"
prefix="$(psd1_value NatPrefix)"
[[ "$mac" =~ ^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$ ]] || die "MacAddress not found or malformed in $psd1"
[[ "$guest" =~ ^[0-9]+(\.[0-9]+){3}$ && "$gateway" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || die "addresses not found in $psd1"
[[ "$prefix" =~ ^[0-9.]+/[0-9]+$ ]] || die "NatPrefix not found in $psd1"
nic_mac="$(printf '%s' "${mac//-/}" | tr 'A-F' 'a-f')"

secret="" work="" stage=""
cleanup() {
  local d
  for d in "$secret" "$work" "$stage"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    find "$d" -type f -size -1024k -exec shred -u {} + 2>/dev/null || true
    rm -r "$d"
  done
}
trap cleanup EXIT

secret="$(mktemp -d /dev/shm/pve-iso.XXXXXX)"
work="$(mktemp -d /tmp/pve-iso.XXXXXX)"
mkdir -p "$(dirname "$out")"
stage="$(mktemp -d "$(dirname "$out")/.pve-iso-stage.XXXXXX")"
partial="$stage/$(basename "$out").partial"

cat > "$secret/render.py" <<'PY'
import json, re, sys
tmpl, pub_op, pub_auto, out, nic_mac, cidr, gateway = sys.argv[1:8]
pw_hash = sys.stdin.read().strip()
if not re.fullmatch(r'\$6\$[^$\s"]+\$[^$\s"]+', pw_hash):
    sys.exit("password hash is not a SHA-512 crypt string")
keys = []
for p in (pub_op, pub_auto):
    k = open(p, encoding="ascii").read().strip()
    if "\n" in k or not k.startswith("ssh-"):
        sys.exit("not a single-line SSH public key: " + p)
    keys.append(json.dumps(k))
text = open(tmpl, encoding="utf-8").read()
for name, value in {
    "ROOT_PASSWORD_HASH": pw_hash,
    "ROOT_SSH_KEYS": ", ".join(keys),
    "NIC_MAC": nic_mac,
    "GUEST_CIDR": cidr,
    "GATEWAY": gateway,
}.items():
    text = text.replace("@@" + name + "@@", value)
left = re.findall(r"@@[A-Z_]+@@", text)
if left:
    sys.exit("unfilled placeholders: " + ", ".join(left))
open(out, "w", encoding="utf-8", newline="\n").write(text)
PY

rendered="$secret/answer.toml"
sops -d --extract '["root_password"]' "$sops_file" | openssl passwd -6 -stdin \
  | python3 -I "$secret/render.py" "$tmpl" "$pub_op" "$pub_auto" "$rendered" "$nic_mac" "${guest}/${prefix#*/}" "$gateway"

# Validator output stays in a file: it echoes the parsed answer, hash included.
validate_rc=0
proxmox-auto-install-assistant validate-answer "$rendered" >"$secret/validate.txt" 2>&1 || validate_rc=$?
echo "validate-answer exit=$validate_rc: $(head -n1 "$secret/validate.txt" | sed -E 's/\$6\$[^"[:space:]]*/<redacted>/g')"
[ "$validate_rc" -eq 0 ] || die "answer file failed validation"

proxmox-auto-install-assistant prepare-iso "$src" --fetch-from iso --answer-file "$rendered" --tmp "$work" --output "$partial" >/dev/null
mv -f "$partial" "$out"
echo "prepared: $out"
echo "sha256 $(sha256sum "$out")"
