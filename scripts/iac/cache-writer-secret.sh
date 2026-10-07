#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
secret_file="${CACHE_WRITER_SECRET_FILE:-iac/secrets/hosts/pve01-cache.sops.yaml}"
secret_name="CACHE_WRITER_PASSWORD"
environment="cache-writer"
min_length=40
cmdexe="/mnt/c/Windows/System32/cmd.exe"
rotate=0
github_repo="${GITHUB_REPOSITORY:-}"
password=""

die() { echo "ERROR: $*" >&2; exit 1; }
winvar() { (cd /mnt/c && "$cmdexe" /c "echo %$1%" 2>/dev/null | tr -d '\r'); }
cleanup() { password=""; unset password; }
trap cleanup EXIT

while [ "$#" -gt 0 ]; do
  case "$1" in
    --rotate) rotate=1 ;;
    --repo) shift; github_repo="${1:-}" ;;
    *) echo "usage: cache-writer-secret.sh [--rotate] [--repo OWNER/REPO]" >&2; exit 2 ;;
  esac
  shift
done

command -v sops >/dev/null || die "sops is not installed (scripts/bootstrap/operator-toolchain.sh)"
command -v gh >/dev/null || die "gh is not installed"

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ ! -f "$HOME/.config/sops/age/keys.txt" ] && [ -x "$cmdexe" ]; then
  appdata="$(winvar APPDATA)"
  [ -n "$appdata" ] && SOPS_AGE_KEY_FILE="$(wslpath -u "$appdata")/sops/age/keys.txt" && export SOPS_AGE_KEY_FILE
fi

[ -n "$github_repo" ] || github_repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)" || die "cannot resolve the GitHub repository; pass --repo OWNER/REPO"
[[ "$github_repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "the repository must look like OWNER/REPO"

cd "$repo"

present=0
if [ -f "$secret_file" ]; then
  length="$(sops decrypt --extract '["writer_password"]' "$secret_file" 2>/dev/null | wc -c)" || length=0
  [ "$length" -gt 0 ] && present=1
fi

if [ "$present" -eq 1 ] && [ "$rotate" -eq 0 ]; then
  echo "$secret_name is already stored in $secret_file; --rotate replaces it in the file and in the GitHub environment"
  exit 0
fi

password="$(head -c 96 /dev/urandom | base64 -w0 | tr -d '/+=' | cut -c1-48)"
[ "${#password}" -ge "$min_length" ] || die "the generated password is shorter than $min_length characters"

if [ ! -f "$secret_file" ]; then
  umask 077
  mkdir -p "$(dirname "$secret_file")"
  printf 'writer_user: ci-writer\n' \
    | sops encrypt --filename-override "$secret_file" --input-type yaml --output-type yaml --output "$secret_file" /dev/stdin \
    || die "cannot create $secret_file"
fi

printf '"%s"' "$password" | sops set --value-stdin "$secret_file" '["writer_password"]' \
  || die "cannot store the password in $secret_file"

printf '%s' "$password" | gh secret set "$secret_name" --env "$environment" --repo "$github_repo" >/dev/null \
  || die "the password is stored in $secret_file but the GitHub environment secret was not set; run again with --rotate"

echo "stored the writer credential in $secret_file and set the secret $secret_name in environment $environment"
