#!python
# WANT_JSON
import json
import os
import sys

NAME = "__NAME__"
KIND = "__KIND__"
out = os.environ["FAKE_ROLE_OUT"]
if KIND == "command":
    args = {"_raw_params": " ".join([NAME] + sys.argv[1:])}
    NAME = "command"
else:
    args = {k: v for k, v in json.load(open(sys.argv[1], encoding="utf-8")).items() if not k.startswith("_ansible_")}
seen = json.dumps(args, sort_keys=True)

with open(os.path.join(out, "calls.jsonl"), "a", encoding="utf-8") as handle:
    handle.write(json.dumps({"module": NAME, "args": args}, sort_keys=True) + "\n")
if NAME == "copy":
    os.makedirs(os.path.join(out, "copy"), exist_ok=True)
    with open(os.path.join(out, "copy", os.path.basename(args["dest"])), "w", encoding="utf-8") as handle:
        handle.write(args.get("content") or "")

scenario = json.load(open(os.environ["FAKE_ROLE_SCENARIO"], encoding="utf-8"))
override = json.loads(os.environ.get("FAKE_ROLE_OVERRIDE") or "{}")
rules = override.get(NAME, []) + scenario.get(NAME, [])
result = {"changed": False}
for index, rule in enumerate(rules):
    if rule.get("when", "") in seen:
        key = "%s:%d" % (NAME, index)
        state_path = os.path.join(out, "state.json")
        state = json.load(open(state_path, encoding="utf-8")) if os.path.exists(state_path) else {}
        used = state.get(key, 0)
        state[key] = used + 1
        json.dump(state, open(state_path, "w", encoding="utf-8"))
        result = rule["seq"][min(used, len(rule["seq"]) - 1)] if "seq" in rule else rule["result"]
        break

if KIND == "command":
    sys.stdout.write(result.get("stdout", "") + "\n")
    sys.stderr.write(result.get("stderr", ""))
    sys.exit(result.get("rc", 0))
print(json.dumps(result))
