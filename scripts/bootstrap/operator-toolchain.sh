#!/usr/bin/env bash
set -euo pipefail

TOFU_VERSION="1.13.1"
TOFU_SHA256="378ada19d4bc70c43732004e8159be771b23b9a5afdf059e5f8a2b3fa2c70a69"
SOPS_VERSION="3.13.3"
SOPS_SHA256="e5bec3346a873ae91d871550f3e698c1aad962aff462a080e40f25fde17fef6b"
GITLEAKS_VERSION="8.30.1"
GITLEAKS_SHA256="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
PVE_KEYRING_SHA256="136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45"
PVE_KEYRING_URL="https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg"
PVE_KEYRING="/usr/share/keyrings/proxmox-archive-keyring.gpg"
PVE_SOURCES="/etc/apt/sources.list.d/proxmox-pve.sources"
PVE_PREFS="/etc/apt/preferences.d/proxmox-pve"
INSTALL_DIR="/usr/local/bin"
APT_PACKAGES=(ca-certificates curl gpg openssl python3 jq age xorriso ansible git openssh-client)

export DEBIAN_FRONTEND=noninteractive
apt_updated=0
tmp_dirs=()
trap 'for d in "${tmp_dirs[@]}"; do rm -rf "$d"; done' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

new_tmp() { local d; d="$(mktemp -d)"; tmp_dirs+=("$d"); echo "$d"; }

apt_update_once() {
  if [ "$apt_updated" -eq 0 ]; then apt-get update -qq; apt_updated=1; fi
}

missing_packages() {
  local p
  for p in "$@"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q '^install ok installed$' || echo "$p"
  done
}

apt_ensure() {
  local missing
  mapfile -t missing < <(missing_packages "$@")
  if [ "${#missing[@]}" -eq 0 ]; then
    echo "apt: 0 newly installed ($*)"
    return
  fi
  apt_update_once
  apt-get install -y -qq "${missing[@]}"
  echo "apt: ${#missing[@]} newly installed (${missing[*]})"
}

verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  [ "$actual" = "$expected" ] || die "sha256 mismatch for $(basename "$file"): expected $expected got $actual"
  echo "sha256 OK $(basename "$file")"
}


write_if_changed() {
  local path="$1" content="$2"
  if [ -f "$path" ] && [ "$(cat "$path")" = "$content" ]; then
    echo "present: $path"
    return 1
  fi
  printf '%s\n' "$content" > "$path"
  echo "written: $path"
}

[ "$(id -u)" -eq 0 ] || die "run as root"
[ "$(uname -m)" = "x86_64" ] || die "amd64 only"

log "Debian archive packages"
apt_ensure "${APT_PACKAGES[@]}"

log "OpenTofu ${TOFU_VERSION}"
if command -v tofu >/dev/null && tofu version | head -n1 | grep -qx "OpenTofu v${TOFU_VERSION}"; then
  echo "present: tofu ${TOFU_VERSION}"
else
  work="$(new_tmp)"
  base="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"
  archive="tofu_${TOFU_VERSION}_linux_amd64.tar.gz"
  curl -fsSL --retry 3 -o "$work/$archive" "$base/$archive"
  verify_sha256 "$work/$archive" "$TOFU_SHA256"
  mkdir "$work/x"
  tar -xzf "$work/$archive" -C "$work/x" tofu
  install -m 0755 "$work/x/tofu" "$INSTALL_DIR/tofu"
fi

log "SOPS ${SOPS_VERSION}"
if command -v sops >/dev/null && sops --disable-version-check --version 2>&1 | grep -q "^sops ${SOPS_VERSION}\b"; then
  echo "present: sops ${SOPS_VERSION}"
else
  work="$(new_tmp)"
  base="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}"
  bin="sops-v${SOPS_VERSION}.linux.amd64"
  curl -fsSL --retry 3 -o "$work/$bin" "$base/$bin"
  verify_sha256 "$work/$bin" "$SOPS_SHA256"
  install -m 0755 "$work/$bin" "$INSTALL_DIR/sops"
fi

log "gitleaks ${GITLEAKS_VERSION}"
if command -v gitleaks >/dev/null && [ "$(gitleaks version)" = "${GITLEAKS_VERSION}" ]; then
  echo "present: gitleaks ${GITLEAKS_VERSION}"
else
  work="$(new_tmp)"
  archive="gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
  curl -fsSL --retry 3 -o "$work/$archive" "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/$archive"
  verify_sha256 "$work/$archive" "$GITLEAKS_SHA256"
  mkdir "$work/x"
  tar -xzf "$work/$archive" -C "$work/x" gitleaks
  install -m 0755 "$work/x/gitleaks" "$INSTALL_DIR/gitleaks"
fi

log "Proxmox VE no-subscription repository"
if [ -f "$PVE_KEYRING" ] && [ "$(sha256sum "$PVE_KEYRING" | cut -d' ' -f1)" = "$PVE_KEYRING_SHA256" ]; then
  echo "present: $PVE_KEYRING"
else
  work="$(new_tmp)"
  curl -fsSL --retry 3 -o "$work/proxmox-archive-keyring-trixie.gpg" "$PVE_KEYRING_URL"
  verify_sha256 "$work/proxmox-archive-keyring-trixie.gpg" "$PVE_KEYRING_SHA256"
  install -m 0644 "$work/proxmox-archive-keyring-trixie.gpg" "$PVE_KEYRING"
fi
echo "keyring sha256 OK $PVE_KEYRING"

write_if_changed "$PVE_SOURCES" "Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: $PVE_KEYRING" && apt_updated=0 || true
write_if_changed "$PVE_PREFS" "Package: *
Pin: origin download.proxmox.com
Pin-Priority: 1" || true

if [ -n "$(missing_packages proxmox-auto-install-assistant)" ]; then
  apt_update_once
  apt-get install -y -qq proxmox-auto-install-assistant
  echo "apt: 1 newly installed (proxmox-auto-install-assistant)"
else
  echo "apt: 0 newly installed (proxmox-auto-install-assistant)"
fi

log "Versions"
row() { printf '%-34s %s\n' "$1" "$2"; }
row tofu "$(tofu version | head -n1)"
row sops "$(sops --disable-version-check --version 2>&1 | head -n1)"
row gitleaks "$(gitleaks version)"
row age "$(age --version)"
row age-keygen "$(age-keygen --version)"
row ansible-package "$(dpkg-query -W -f='${Version}' ansible)"
row ansible "$(ansible --version | head -n1)"
row ansible-playbook "$(ansible-playbook --version | head -n1)"
row xorriso "$(xorriso -version 2>&1 | grep -m1 'xorriso 1')"
row proxmox-auto-install-assistant "$(dpkg-query -W -f='${Version}' proxmox-auto-install-assistant)"
row python3 "$(python3 --version)"
row openssl "$(openssl version)"
row jq "$(jq --version)"
row curl "$(curl --version | head -n1)"
row gpg "$(gpg --version | head -n1)"
row ssh "$(ssh -V 2>&1)"
row ssh-keygen "$(dpkg-query -W -f='openssh-client ${Version}' openssh-client)"
row git "$(git --version)"
