import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SCRIPT = REPO / "scripts" / "ci" / "select-runner.sh"
RUNNER_TOKEN = "runner-status-token-value"
RUN_TOKEN = "github-token-value"
STUB = """#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
out, url = args[args.index("-o") + 1], args[-1]
stub = os.environ["STUB_DIR"]
with open(os.path.join(stub, "calls.log"), "a") as log:
    log.write(url + " " + sys.stdin.read().strip() + "\\n")
for suffix, (code, body) in json.load(open(os.path.join(stub, "routes.json"))).items():
    if url.endswith(suffix):
        open(out, "w").write(body)
        sys.stdout.write(str(code))
        sys.exit(0)
sys.stderr.write("curl: (6) Could not resolve host\\n")
sys.stdout.write("000")
sys.exit(6)
"""


def text(path):
    return path.read_text(encoding="utf-8")


def runners(status="online"):
    doc = json.loads(text(FIXTURES / "runners-online.json"))
    for runner in doc["runners"]:
        runner["status"] = status
    return json.dumps(doc)


def previous_attempt(scenario):
    base = FIXTURES / scenario
    routes = {"/runs/9/attempts/1/jobs?per_page=100": [200, text(base / "jobs.json")]}
    for path in (base / "annotations").glob("*.json"):
        routes[f"/check-runs/{path.stem}/annotations"] = [200, text(path)]
    return routes


@unittest.skipIf(os.name == "nt" or not shutil.which("jq"), "needs a POSIX shell and jq")
class SelectRunnerTests(unittest.TestCase):
    def run_script(self, routes, attempt=1, forced="false", token=RUNNER_TOKEN):
        with tempfile.TemporaryDirectory() as d:
            stub = Path(d)
            (stub / "curl").write_text(STUB, encoding="utf-8")
            (stub / "curl").chmod(0o755)
            (stub / "routes.json").write_text(json.dumps(routes), encoding="utf-8")
            env = dict(os.environ, PATH=f"{stub}:{os.environ['PATH']}", STUB_DIR=str(stub), FORCED_HOSTED=forced,
                       RUNNER_STATUS_TOKEN=token, GH_TOKEN=RUN_TOKEN, REPOSITORY="owner/repo", RUN_ID="9", RUN_ATTEMPT=str(attempt),
                       GITHUB_API_URL="https://api.example.invalid", GITHUB_OUTPUT=str(stub / "output"), GITHUB_STEP_SUMMARY=str(stub / "summary"))
            done = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            outputs = dict(line.split("=", 1) for line in text(stub / "output").splitlines())
            calls = text(stub / "calls.log").splitlines() if (stub / "calls.log").exists() else []
            visible = done.stdout + done.stderr + text(stub / "output") + text(stub / "summary")
            self.assertNotIn(RUNNER_TOKEN, visible)
            self.assertNotIn(RUN_TOKEN, visible)
            return outputs, calls, done.stdout, text(stub / "summary")

    def test_online_runners_route_to_proxmox_and_the_summary_says_why(self):
        outputs, calls, _, summary = self.run_script({"/actions/runners?per_page=100": [200, runners()]})
        self.assertEqual(outputs["hosted"], "false")
        self.assertEqual(outputs["dotnet_labels"], '["self-hosted", "linux", "proxmox", "dotnet"]')
        self.assertIn("3 of 3 Proxmox runners online (HTTP 200)", outputs["route_reason"])
        self.assertIn("Runner route (attempt 1)", summary)
        self.assertEqual(calls, [f"https://api.example.invalid/repos/owner/repo/actions/runners?per_page=100 Authorization: Bearer {RUNNER_TOKEN}"])

    def test_no_online_runner_routes_hosted(self):
        outputs, _, _, _ = self.run_script({"/actions/runners?per_page=100": [200, runners("offline")]})
        self.assertEqual(outputs["hosted"], "true")
        self.assertEqual(outputs["dotnet_labels"], '["ubuntu-latest"]')
        self.assertIn("no Proxmox runner online", outputs["route_reason"])

    def test_a_rejected_token_falls_back_and_prints_the_api_message(self):
        outputs, _, stdout, _ = self.run_script({"/actions/runners?per_page=100": [401, '{"message": "Bad credentials"}']})
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("HTTP 401", outputs["route_reason"])
        self.assertIn("Bad credentials", stdout)

    def test_an_unreachable_api_falls_back(self):
        outputs, _, stdout, _ = self.run_script({})
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("HTTP 0", outputs["route_reason"])
        self.assertIn("Could not resolve host", stdout)

    def test_without_a_token_nothing_is_called(self):
        outputs, calls, _, _ = self.run_script({}, token="")
        self.assertEqual(calls, [])
        self.assertIn("no RUNNER_STATUS_TOKEN", outputs["route_reason"])

    def test_forced_hosted_calls_nothing(self):
        outputs, calls, _, _ = self.run_script({}, forced="true")
        self.assertEqual((outputs["hosted"], calls), ("true", []))

    def test_an_infra_failure_in_attempt_one_routes_attempt_two_hosted_with_the_run_token(self):
        outputs, calls, _, summary = self.run_script(previous_attempt("runner-restarted"), attempt=2)
        self.assertEqual(outputs["hosted"], "true")
        self.assertIn("Execute Transitive Affected Tests", outputs["route_reason"])
        self.assertIn("Runner route (attempt 2)", summary)
        self.assertTrue(calls)
        self.assertTrue(all(call.endswith(f"Bearer {RUN_TOKEN}") for call in calls), calls)

    def test_a_test_failure_in_attempt_one_goes_back_to_the_health_check(self):
        routes = previous_attempt("test-failure")
        routes["/actions/runners?per_page=100"] = [200, runners()]
        outputs, calls, _, _ = self.run_script(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertTrue(calls[-1].endswith(f"Bearer {RUNNER_TOKEN}"))

    def test_an_unreadable_previous_attempt_is_noted_and_not_treated_as_infra(self):
        routes = {"/runs/9/attempts/1/jobs?per_page=100": [404, '{"message": "Not Found"}'], "/actions/runners?per_page=100": [200, runners()]}
        outputs, _, _, _ = self.run_script(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("jobs of attempt 1 returned HTTP 404", outputs["route_reason"])

    def test_a_missing_annotation_keeps_the_previous_attempt_unclassified(self):
        routes = previous_attempt("runner-restarted")
        routes = {k: v for k, v in routes.items() if "check-runs/113276599473" not in k}
        routes["/actions/runners?per_page=100"] = [200, runners()]
        outputs, _, _, _ = self.run_script(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("annotations of attempt 1 returned HTTP 000", outputs["route_reason"])


if __name__ == "__main__":
    unittest.main()
