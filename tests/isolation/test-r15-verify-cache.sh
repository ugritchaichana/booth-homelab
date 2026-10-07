#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playbook="${R15_VERIFY_PLAYBOOK:-$repo/iac/ansible/playbooks/r15-verify.yml}"

command -v ansible-playbook > /dev/null || { echo "ERROR: ansible-playbook is not installed" >&2; exit 2; }
[ -f "$playbook" ] || { echo "ERROR: no playbook at $playbook" >&2; exit 2; }

py="$(head -n1 "$(command -v ansible-playbook)" | sed 's/^#! *//; s/ .*//')"
[ -x "$py" ] || py=python3

ANSIBLE_CONFIG="$repo/iac/ansible/ansible.cfg" ansible-playbook --syntax-check "$playbook" > /dev/null \
  || { echo "FAIL: r15-verify.yml does not pass the syntax check" >&2; exit 1; }

"$py" -I - "$playbook" << 'PY'
import ast
import json
import sys

import jinja2
import yaml

plays = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
play = next(p for p in plays if p.get("hosts") == "pve_hosts" and "r15_phases" in p.get("vars", {}))
errors = []


def fail(message):
    errors.append(message)


def flatten(tasks, section=None):
    for task in tasks:
        if "block" in task:
            yield from flatten(task["block"], "block")
            yield from flatten(task.get("rescue", []), "rescue")
            yield from flatten(task.get("always", []), "always")
        else:
            yield task, section


tasks = list(flatten(play["tasks"]))
by_name = {t["name"]: (t, section) for t, section in tasks}

env = jinja2.Environment()
env.filters["dict2items"] = lambda d: [{"key": k, "value": v} for k, v in d.items()]
env.filters["string"] = str
env.filters["from_json"] = json.loads
env.filters["bool"] = lambda v: str(v).lower() in ("true", "1", "yes")
env.filters["difference"] = lambda a, b: [x for x in a if x not in b]


def walk(value, ctx):
    if isinstance(value, list):
        return [walk(item, ctx) for item in value]
    if isinstance(value, str) and "{{" in value:
        out = env.from_string(value).render(**ctx)
        try:
            return ast.literal_eval(out)
        except (ValueError, SyntaxError):
            return out
    return value


def context_for(cache, **extra):
    ctx = dict(play["vars"])
    ctx.update({"r15_phase": "baseline", "r15_control_key": "/key", "pve_node_name": "n1"})
    ctx["r15_guests"] = {
        "lxc": {"login_user": "root", "address": "10.99.16.21", "vm_id": 9101},
        "vm": {"login_user": "debian", "address": "10.99.16.22", "vm_id": 9102},
    }
    if cache:
        ctx["cache_endpoint"] = {"address": "10.99.17.10", "port": 8080}
    ctx.update(extra)
    raw = dict(ctx)
    for _ in range(6):
        ctx = {key: walk(value, ctx) for key, value in raw.items()}
    return ctx


def argv(task_name, ctx, guest=None):
    task, _ = by_name[task_name]
    text = task["ansible.builtin.command"]["argv"]
    local = dict(ctx)
    if guest is not None:
        local["r15_guest"] = guest
    value = env.from_string(text).render(**local) if isinstance(text, str) else text
    return ast.literal_eval(value) if isinstance(value, str) else [env.from_string(str(x)).render(**local) for x in value]


probe = "Run the probe in each guest"
lxc = {"key": "lxc", "value": {"login_user": "root", "address": "10.99.16.21"}}
vm = {"key": "vm", "value": {"login_user": "debian", "address": "10.99.16.22"}}

with_cache = context_for(True)
for guest in (lxc, vm):
    remote = argv(probe, with_cache, guest)[-1]
    if "CACHE_ADDR=10.99.17.10 CACHE_PORT=8080 bash" not in remote:
        fail("the %s runner probe does not pass CACHE_ADDR and CACHE_PORT: %r" % (guest["key"], remote))
if not argv(probe, with_cache, vm)[-1].startswith("sudo -n env CACHE_ADDR="):
    fail("the vm probe must keep sudo in front of the env assignment")
without = argv(probe, context_for(False), lxc)[-1]
if "CACHE_" in without:
    fail("a host with no cache_endpoint must pass no cache variable: %r" % without)

run = argv("Run the probe in the cache container", with_cache, {"key": "cache"})
expected_head = ["pct", "exec", "9050", "--", "bash", "/tmp/r15/r15-probe.sh", "--guest", "cache", "--phase", "baseline"]
if run[: len(expected_head)] != expected_head:
    fail("the cache probe command is %r, expected it to start with %r" % (run, expected_head))
if any("CACHE_" in part for part in run):
    fail("the cache probe must not receive the cache variables")

override = context_for(True, r15_cache_vmid=9777)
if argv("Run the probe in the cache container", override, {"key": "cache"})[2] != "9777":
    fail("r15_cache_vmid must override the container id")

cleanup, section = by_name["Remove the probe and the targets from the cache container"]
if section != "always":
    fail("the container cleanup must sit in an always section")
if argv("Remove the probe and the targets from the cache container", with_cache) != ["pct", "exec", "9050", "--", "rm", "-rf", "/tmp/r15"]:
    fail("the container cleanup must run rm -rf /tmp/r15 inside the cache container")
stage_cleanup, section = by_name["Remove the staged copies from the host"]
if section != "always" or stage_cleanup["ansible.builtin.file"]["state"] != "absent":
    fail("the host staging directory must be removed in an always section")

def running(*vmids):
    return json.dumps([{"vmid": v, "status": "running"} for v in vmids] + [{"vmid": 1, "status": "stopped"}])


def refusal_holds(ctx, *vmids):
    task, _ = by_name["Refuse the red-first run while any other guest is running"]
    local = dict(ctx, r15_phase="red-first", r15_resources={"stdout": running(*vmids)})
    return all(env.compile_expression(c.strip())(**local) for c in task["ansible.builtin.assert"]["that"])


red_cache = context_for(True)
if red_cache["r15_red_first_allowed_vmids"] != [9050]:
    fail("the red-first allowed list must hold the cache vmid when the host has a cache endpoint: %r" % red_cache["r15_red_first_allowed_vmids"])
if context_for(False)["r15_red_first_allowed_vmids"] != []:
    fail("a host with no cache endpoint must allow no extra guest in the red-first run")
if not refusal_holds(red_cache, 9101, 9102, 9050):
    fail("the red-first run must accept the cache container running next to the probes")
if refusal_holds(red_cache, 9101, 9102, 9050, 9999):
    fail("the red-first run must still refuse any other running guest")
if refusal_holds(context_for(False), 9101, 9102, 9050):
    fail("without a cache endpoint the cache vmid is not allowed to run in the red-first run")
if not refusal_holds(red_cache, 9101, 9102):
    fail("the red-first run must accept probes alone")
shown = env.from_string(by_name["Show which allowed guest stays up during the red-first run"][0]["ansible.builtin.debug"]["msg"]).render(
    **dict(red_cache, r15_resources={"stdout": running(9101, 9050)})
)
if "[9050]" not in shown:
    fail("the red-first run must print which allowed guest stayed up: %r" % shown)

keygen = next(p for p in plays if "r15_keygen" in p.get("tags", []))
forget = next((t for t in keygen["tasks"] if t["name"] == "Forget the guest host keys of the previous probe generation"), None)
if forget is None or forget["ansible.builtin.file"].get("state") != "absent" or forget["ansible.builtin.file"].get("path") != "{{ r15_known_hosts }}":
    fail("the keygen play must delete the probe known_hosts file so each probe generation starts clean")
elif keygen["tasks"][0] is not forget:
    fail("the known_hosts file must be deleted before the key is generated")
if "UserKnownHostsFile={{ r15_known_hosts }}" not in play["vars"]["r15_ssh_base"] or "StrictHostKeyChecking=accept-new" not in play["vars"]["r15_ssh_base"]:
    fail("the probe ssh options must use the same known_hosts file with accept-new inside a generation")
if "r15_known_hosts" not in open(sys.argv[1].replace("playbooks/r15-verify.yml", "../tofu/stacks/r15-probe/probe.yml"), encoding="utf-8").read():
    fail("probe.yml must define r15_known_hosts")

fetch, _ = by_name["Fetch every output to this machine"]
if "'cache'" not in fetch["loop"] or "r15_cache_enabled" not in fetch["loop"]:
    fail("the fetch loop must add the cache output when the cache is enabled")
for name in ("Keep each probe output on the host", "Show each summary line", "Fail unless every probe exited 0"):
    if "r15_cache_runs" not in by_name[name][0]["loop"]:
        fail("%r does not cover the cache run" % name)

if errors:
    for message in errors:
        print("FAIL: " + message)
    sys.exit(1)
print("OK: r15-verify.yml passes the probe the cache address, runs inside the cache container and cleans up")
PY
