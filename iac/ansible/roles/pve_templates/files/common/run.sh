#!/bin/sh
set -eu

build_id="${1:?usage: run.sh <build_id>}"
root="${FINALIZE_ROOT:-}"
here="$(cd "$(dirname "$0")" && pwd)"
installed_ansible=0

if ! command -v ansible-playbook >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends ansible-core
  installed_ansible=1
fi

mkdir -p "$root/var/lib/homelab-build"
ANSIBLE_LOCALHOST_WARNING=False ansible-playbook -c local -i localhost, "$here/playbook.yml" -e "build_id=$build_id" -e "manifest_path=$root/var/lib/homelab-build/manifest.json"

if [ "$installed_ansible" -eq 1 ]; then
  apt-get purge -y -qq ansible-core
  apt-get autoremove -y -qq --purge
fi

sh "$here/finalize.sh" "$build_id"
