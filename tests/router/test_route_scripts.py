import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
SELECT = REPO / "scripts" / "ci" / "select-runner.sh"
CLASSIFY = REPO / "scripts" / "ci" / "sdet-classify.sh"
RUNNER_TOKEN = "runner-status-token-value"
RUN_TOKEN = "github-token-value"
WRAPPER = os.environ.get("SCRIPT_COVERAGE", "").split()
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


def attempt_routes(scenario, attempt=1):
    doc = json.loads(text(FIXTURES / f"{scenario}.json"))
    routes = {f"/runs/9/attempts/{attempt}/jobs?per_page=100": [200, json.dumps(doc["jobs"])]}
    for job_id, annotations in doc["annotations"].items():
        routes[f"/check-runs/{job_id}/annotations"] = [200, json.dumps(annotations)]
    return routes


def previous_attempt(scenario):
    return attempt_routes(scenario)


def hosted_success(attempt):
    doc = json.loads(text(FIXTURES / "runner-restarted.json"))["jobs"]
    for job in doc["jobs"]:
        job.update(labels=["ubuntu-latest"], runner_name="GitHub Actions 1", conclusion="success" if job["conclusion"] == "failure" else job["conclusion"])
    return {f"/runs/9/attempts/{attempt}/jobs?per_page=100": [200, json.dumps(doc)]}


def run_doc(attempt, conclusion):
    return {"/actions/runs/9": [200, json.dumps({"id": 9, "run_attempt": attempt, "conclusion": conclusion})]}


class ScriptCase(unittest.TestCase):
    def run_script(self, script, routes, expect_rc=0, **env_overrides):
        with tempfile.TemporaryDirectory() as d:
            stub = Path(d)
            (stub / "curl").write_text(STUB, encoding="utf-8")
            (stub / "curl").chmod(0o755)
            (stub / "routes.json").write_text(json.dumps(routes), encoding="utf-8")
            (stub / "output").write_text("", encoding="utf-8")
            (stub / "summary").write_text("", encoding="utf-8")
            env = dict(os.environ, PATH=f"{stub}:{os.environ['PATH']}", STUB_DIR=str(stub), FORCED_HOSTED="false",
                       RUNNER_STATUS_TOKEN=RUNNER_TOKEN, GH_TOKEN=RUN_TOKEN, REPOSITORY="owner/repo", RUN_ID="9", RUN_ATTEMPT="1",
                       GITHUB_API_URL="https://api.example.invalid", GITHUB_OUTPUT=str(stub / "output"), GITHUB_STEP_SUMMARY=str(stub / "summary"))
            env.update(env_overrides)
            command = WRAPPER + [str(script)] if WRAPPER else ["bash", str(script)]
            done = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(done.returncode, expect_rc, done.stdout + done.stderr)
            outputs = dict(line.split("=", 1) for line in text(stub / "output").splitlines())
            calls = text(stub / "calls.log").splitlines() if (stub / "calls.log").exists() else []
            visible = done.stdout + done.stderr + text(stub / "output") + text(stub / "summary")
            self.assertNotIn(RUNNER_TOKEN, visible)
            self.assertNotIn(RUN_TOKEN, visible)
            return outputs, calls, done.stdout + done.stderr, text(stub / "summary")


@unittest.skipIf(os.name == "nt" or not shutil.which("jq"), "needs a POSIX shell and jq")
class SelectRunnerTests(ScriptCase):
    def run_select(self, routes, attempt=1, forced="false", token=RUNNER_TOKEN):
        return self.run_script(SELECT, routes, RUN_ATTEMPT=str(attempt), FORCED_HOSTED=forced, RUNNER_STATUS_TOKEN=token)

    def test_online_runners_route_to_proxmox_and_the_summary_says_why(self):
        outputs, calls, _, summary = self.run_select({"/actions/runners?per_page=100": [200, runners()]})
        self.assertEqual(outputs["hosted"], "false")
        self.assertEqual(outputs["dotnet_labels"], '["self-hosted", "linux", "proxmox", "dotnet"]')
        self.assertIn("3 of 3 Proxmox runners online (HTTP 200)", outputs["route_reason"])
        self.assertIn("Runner route (attempt 1)", summary)
        self.assertEqual(calls, [f"https://api.example.invalid/repos/owner/repo/actions/runners?per_page=100 Authorization: Bearer {RUNNER_TOKEN}"])

    def test_no_online_runner_routes_hosted(self):
        outputs, _, _, _ = self.run_select({"/actions/runners?per_page=100": [200, runners("offline")]})
        self.assertEqual(outputs["hosted"], "true")
        self.assertEqual(outputs["dotnet_labels"], '["ubuntu-latest"]')
        self.assertIn("no Proxmox runner online", outputs["route_reason"])

    def test_a_rejected_token_falls_back_and_prints_the_api_message(self):
        outputs, _, stdout, _ = self.run_select({"/actions/runners?per_page=100": [401, '{"message": "Bad credentials"}']})
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("HTTP 401", outputs["route_reason"])
        self.assertIn("Bad credentials", stdout)

    def test_an_unreachable_api_falls_back(self):
        outputs, _, stdout, _ = self.run_select({})
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("HTTP 0", outputs["route_reason"])
        self.assertIn("Could not resolve host", stdout)

    def test_without_a_token_nothing_is_called(self):
        outputs, calls, _, _ = self.run_select({}, token="")
        self.assertEqual(calls, [])
        self.assertIn("no RUNNER_STATUS_TOKEN", outputs["route_reason"])

    def test_forced_hosted_calls_nothing(self):
        outputs, calls, _, _ = self.run_select({}, forced="true")
        self.assertEqual((outputs["hosted"], calls), ("true", []))

    def test_an_infra_failure_in_attempt_one_routes_attempt_two_hosted_with_the_run_token(self):
        outputs, calls, _, summary = self.run_select(previous_attempt("runner-restarted"), attempt=2)
        self.assertEqual(outputs["hosted"], "true")
        self.assertIn("Execute Transitive Affected Tests", outputs["route_reason"])
        self.assertIn("Runner route (attempt 2)", summary)
        self.assertTrue(calls)
        self.assertTrue(all(call.endswith(f"Bearer {RUN_TOKEN}") for call in calls), calls)

    def test_a_test_failure_in_attempt_one_goes_back_to_the_health_check(self):
        routes = previous_attempt("test-failure")
        routes["/actions/runners?per_page=100"] = [200, runners()]
        outputs, calls, _, _ = self.run_select(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertTrue(calls[-1].endswith(f"Bearer {RUNNER_TOKEN}"))

    def test_an_unreadable_previous_attempt_is_noted_and_not_treated_as_infra(self):
        routes = {"/runs/9/attempts/1/jobs?per_page=100": [404, '{"message": "Not Found"}'], "/actions/runners?per_page=100": [200, runners()]}
        outputs, _, _, _ = self.run_select(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("jobs of attempt 1 returned HTTP 404", outputs["route_reason"])

    def test_a_missing_annotation_keeps_the_previous_attempt_unclassified(self):
        routes = previous_attempt("runner-restarted")
        routes = {k: v for k, v in routes.items() if "check-runs/113276599473" not in k}
        routes["/actions/runners?per_page=100"] = [200, runners()]
        outputs, _, _, _ = self.run_select(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("annotations of attempt 1 returned HTTP 000", outputs["route_reason"])

    def test_an_unreadable_jobs_document_is_noted_and_not_treated_as_infra(self):
        routes = {"/runs/9/attempts/1/jobs?per_page=100": [200, "not json"], "/actions/runners?per_page=100": [200, runners()]}
        outputs, _, _, _ = self.run_select(routes, attempt=2)
        self.assertEqual(outputs["hosted"], "false")
        self.assertIn("jobs of attempt 1 are not readable", outputs["route_reason"])


@unittest.skipIf(os.name == "nt" or not shutil.which("jq"), "needs a POSIX shell and jq")
class SdetClassifyTests(ScriptCase):
    def classify(self, routes, expect_rc=0, **env):
        return self.run_script(CLASSIFY, routes, expect_rc, RUNNER_STATUS_TOKEN="", **env)

    def test_an_infra_failure_on_attempt_one_asks_for_the_retry(self):
        outputs, calls, _, summary = self.classify({**run_doc(1, "failure"), **attempt_routes("runner-restarted")})
        self.assertEqual(outputs["retry"], "true")
        self.assertIn("Execute Transitive Affected Tests", outputs["note"])
        self.assertIn(outputs["note"], summary)
        self.assertTrue(all(call.endswith(f"Bearer {RUN_TOKEN}") for call in calls), calls)

    def test_a_test_failure_is_not_retried_and_says_why(self):
        outputs, _, _, _ = self.classify({**run_doc(1, "failure"), **attempt_routes("test-failure")})
        self.assertEqual(outputs["retry"], "false")
        self.assertIn("Not retried", outputs["note"])

    def test_the_retried_attempt_names_the_first_failure(self):
        routes = {**run_doc(2, "success"), **hosted_success(2), **attempt_routes("runner-restarted")}
        outputs, _, _, _ = self.classify(routes)
        self.assertEqual(outputs["retry"], "false")
        self.assertTrue(outputs["note"].startswith("Attempt 1 failed on the Proxmox runner (job "), outputs["note"])
        self.assertTrue(outputs["note"].endswith("this attempt ran on GitHub-hosted."))

    def test_a_passing_run_gets_no_retry_and_no_note(self):
        outputs, calls, _, _ = self.classify({**run_doc(1, "success"), **hosted_success(1)})
        self.assertEqual((outputs["retry"], outputs["note"]), ("false", ""))
        self.assertFalse(any("check-runs" in call for call in calls))

    def test_an_unreadable_attempt_is_not_retried(self):
        routes = {**run_doc(1, "failure"), "/runs/9/attempts/1/jobs?per_page=100": [502, '{"message": "Server Error"}']}
        outputs, _, _, _ = self.classify(routes)
        self.assertEqual(outputs["retry"], "false")
        self.assertIn("returned HTTP 502", outputs["note"])

    def test_an_unreadable_run_fails_the_step(self):
        _, _, printed, _ = self.classify({"/actions/runs/9": [404, '{"message": "Not Found"}']}, expect_rc=1)
        self.assertIn("HTTP 404", printed)
        self.assertIn("Not Found", printed)

    def test_a_run_id_that_is_not_a_number_is_refused(self):
        _, calls, printed, _ = self.classify({}, expect_rc=1, RUN_ID="9; echo x")
        self.assertEqual(calls, [])
        self.assertIn("RUN_ID must be a number", printed)


if __name__ == "__main__":
    unittest.main()
