#!/usr/bin/env bash
# Sourced by test-role-*.sh: runs a role copy against fake modules, so no host is touched.
lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAKED_MODULES="apt stat reboot slurp deb822_repository copy package_facts service_facts modprobe"
REAL_MODULES="ansible.builtin.assert ansible.builtin.command ansible.builtin.import_tasks ansible.builtin.shell"
runs=0

# fake_role_prepare <role> <role directory> <external command>...: the role's commands are replaced by stubs
fake_role_prepare() {
  local name="$1" src="$2" module unfaked tool
  shift 2
  mkdir -p "$work/roles" "$work/library" "$work/bin"
  cp -R "$src" "$work/roles/$name"
  : > "$work/ansible.cfg"
  for module in $FAKED_MODULES; do
    sed -i -E "s/(ansible\.builtin|community\.general)\.$module:/fake_$module:/" "$work/roles/$name"/tasks/*.yml
    sed "s/__NAME__/$module/; s/__KIND__/module/" "$lib/fake-role-module.py" > "$work/library/fake_$module.py"
  done
  sed -i -E '/^[[:space:]]+(async|poll):/d' "$work/roles/$name"/tasks/*.yml
  for tool in "$@"; do
    sed "1s|.*|#!/usr/bin/env python3|; s/__NAME__/$tool/; s/__KIND__/command/" "$lib/fake-role-module.py" > "$work/bin/$tool"
    chmod +x "$work/bin/$tool"
  done
  for tool in $(grep -hoE 'ansible\.builtin\.command: *[^ ]+' "$work/roles/$name"/tasks/*.yml | sed -E 's/.*: *//'); do
    [ -x "$work/bin/$tool" ] || { echo "ERROR: $name runs $tool, which has no stub" >&2; exit 2; }
  done
  unfaked="$(grep -hoE '^[[:space:]]*(- )?[a-z_0-9]+\.[a-z_0-9]+\.[a-z_0-9]+:' "$work/roles/$name"/tasks/*.yml | tr -d ' :-' | sort -u | grep -vxF "$(printf '%s\n' $REAL_MODULES)" || true)"
  [ -z "$unfaked" ] || { echo "ERROR: $name uses a module with no fake: $unfaked" >&2; exit 2; }
}

# fake_role_run <role> <tasks file> <scenario file> [ansible-playbook arguments]; sets rc and out
fake_role_run() {
  local name="$1" tasks="$2" scenario="$3"
  shift 3
  runs=$((runs + 1))
  out="$work/out$runs"
  mkdir -p "$out"
  cat > "$work/play.yml" <<YML
- hosts: localhost
  gather_facts: false
  tasks:
    - ansible.builtin.include_role: {name: $name, tasks_from: $tasks}
YML
  rc=0
  FAKE_ROLE_OUT="$out" FAKE_ROLE_SCENARIO="$scenario" ANSIBLE_CONFIG="$work/ansible.cfg" ANSIBLE_LIBRARY="$work/library" \
    ANSIBLE_ROLES_PATH="$work/roles" ANSIBLE_NOCOLOR=1 ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    PATH="$work/bin:$PATH" ansible-playbook -i localhost, -c local "$work/play.yml" "$@" > "$work/run.log" 2>&1 || rc=$?
}

# call_count <module> [needle...]: recorded calls of the fake module whose arguments contain every needle
call_count() {
  local lines needle
  lines="$(grep -F "\"module\": \"$1\"" "$out/calls.jsonl" 2>/dev/null || true)"
  shift
  for needle in "$@"; do lines="$(printf '%s\n' "$lines" | grep -F -- "$needle" || true)"; done
  if [ -z "$lines" ]; then echo 0; else printf '%s\n' "$lines" | wc -l; fi
}

failures=0
b64() { printf '%s' "$1" | base64 -w0; }
jstr() { python3 -I -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"; }
# rule <command text> <stdout> [rc]: a scenario rule answering a command whose arguments contain the text
rule() { printf '{"when": %s, "result": {"rc": %s, "stdout": %s, "stderr": ""}}' "$(jstr "$1")" "${3:-0}" "$(jstr "$2")"; }

verdict() { [ "$2" = "$3" ] || { echo "FAIL: $1 (got $2, want $3)"; failures=$((failures + 1)); }; }
# run <case> [scenario override JSON] [ansible-playbook arguments]; needs ROLE_NAME and BASE_SCENARIO, TASKS_FROM is optional
run() { FAKE_ROLE_OVERRIDE="${2:-}" fake_role_run "$ROLE_NAME" "${TASKS_FROM:-main}" "$BASE_SCENARIO" "${@:3}"; }
should_pass() { verdict "$1 passes" "$rc" 0; }
should_fail() {
  verdict "$1 stops the play" "$([ "$rc" -ne 0 ] && echo stopped || echo continued)" stopped
  grep -qF -- "$2" "$work/run.log" || { echo "FAIL: $1 does not say: $2"; failures=$((failures + 1)); }
}
finish() {
  [ "$failures" -eq 0 ] || { echo "FAIL: $failures expectation(s) broken"; exit 1; }
  echo "OK: $1"
}
