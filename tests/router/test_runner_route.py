import copy
import io
import json
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(REPO / "scripts" / "ci"))

import runner_route  # noqa: E402

RESTARTED = FIXTURES / "runner-restarted.json"
TEST_FAILURE = FIXTURES / "test-failure.json"
DOTNET_JOB = "CI / Build and Test (.NET)"
CANCELLED_STEP = "Execute Transitive Affected Tests (Unit & Integration)"
TIMEOUT = "The job running on runner pve01-ci-lxc-runner-1 has exceeded the maximum execution time of 30 minutes."
SHUTDOWN = "The runner has received a shutdown signal. This can happen when the runner service is stopped, or a manually started runner is canceled."
LOST = "The self-hosted runner: pve01-ci-lxc-runner-1 lost communication with the server. Verify the machine is running and has a healthy network connection."


def scenario(path):
    doc = json.loads(path.read_text(encoding="utf-8"))
    return doc["jobs"]["jobs"], {int(k): v for k, v in doc["annotations"].items()}


def unpacked(path, into):
    doc = json.loads(path.read_text(encoding="utf-8"))
    (into / "annotations").mkdir()
    (into / "jobs.json").write_text(json.dumps(doc["jobs"]), encoding="utf-8")
    for job_id, annotations in doc["annotations"].items():
        (into / "annotations" / f"{job_id}.json").write_text(json.dumps(annotations), encoding="utf-8")
    return ["--jobs", str(into / "jobs.json"), "--annotations-dir", str(into / "annotations")]


def runners():
    return json.loads((FIXTURES / "runners-online.json").read_text(encoding="utf-8"))


def dotnet(jobs):
    return next(j for j in jobs if j["name"] == DOTNET_JOB)


def failure(message):
    return [{"annotation_level": "failure", "title": "", "message": message}]


class FingerprintTests(unittest.TestCase):
    def test_runner_restarted_mid_job_is_infra(self):
        found = runner_route.infra_fingerprint(*scenario(RESTARTED))
        self.assertIsNotNone(found)
        self.assertIn(DOTNET_JOB, found)
        self.assertIn(CANCELLED_STEP, found)

    def test_real_test_failures_are_not_infra(self):
        self.assertIsNone(runner_route.infra_fingerprint(*scenario(TEST_FAILURE)))

    def test_the_hosted_report_job_alone_is_never_infra(self):
        jobs, annotations = scenario(RESTARTED)
        report = [j for j in jobs if j["name"] == "CI / Report"]
        self.assertEqual(report[0]["conclusion"], "failure")
        self.assertIsNone(runner_route.infra_fingerprint(report, annotations))

    def test_mutation_cancelled_step_turned_into_a_failed_step_is_not_infra(self):
        jobs, annotations = scenario(RESTARTED)
        step = next(s for s in dotnet(jobs)["steps"] if s["name"] == CANCELLED_STEP)
        step["conclusion"] = "failure"
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_a_timeout_is_not_infra(self):
        jobs, annotations = scenario(RESTARTED)
        annotations[dotnet(jobs)["id"]] = failure(TIMEOUT)
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_documented_runner_loss_messages_are_infra_even_with_a_failed_step(self):
        for message, phrase in ((SHUTDOWN, "shutdown signal"), (LOST, "lost communication")):
            with self.subTest(phrase=phrase):
                jobs, annotations = scenario(TEST_FAILURE)
                failed = [j for j in jobs if j["conclusion"] == "failure" and "proxmox" in j["labels"]]
                for job in failed:
                    annotations[job["id"]] = failure(message)
                found = runner_route.infra_fingerprint(jobs, annotations)
                self.assertIsNotNone(found)
                self.assertIn(phrase, found)

    def test_a_proxmox_job_that_no_runner_picked_up_is_infra(self):
        jobs, annotations = scenario(RESTARTED)
        job = dotnet(jobs)
        job.update(runner_name=None, steps=[])
        found = runner_route.infra_fingerprint(jobs, {})
        self.assertIsNotNone(found)
        self.assertIn("no runner", found)

    def test_a_hosted_job_without_a_runner_is_not_considered(self):
        jobs, _ = scenario(RESTARTED)
        job = dotnet(jobs)
        job.update(runner_name=None, steps=[], labels=["ubuntu-latest"])
        self.assertIsNone(runner_route.infra_fingerprint([job], {}))

    def test_setup_and_checkout_failures_are_infra(self):
        for name in ("Set up job", "Checkout Repository"):
            with self.subTest(step=name):
                jobs, annotations = scenario(RESTARTED)
                for step in dotnet(jobs)["steps"]:
                    step["conclusion"] = "failure" if step["name"] == name else "success"
                annotations[dotnet(jobs)["id"]] = failure("Process completed with exit code 128.")
                found = runner_route.infra_fingerprint(jobs, annotations)
                self.assertIsNotNone(found)
                self.assertIn(name, found)

    def test_guard_and_compile_failures_are_not_infra(self):
        for name in ("Set up runner", "Compile Solution (/p:Deterministic=true)"):
            with self.subTest(step=name):
                jobs, annotations = scenario(RESTARTED)
                for step in dotnet(jobs)["steps"]:
                    step["conclusion"] = "failure" if step["name"] == name else "success"
                self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_a_real_failure_in_another_job_vetoes_the_retry(self):
        jobs, annotations = scenario(RESTARTED)
        angular = next(j for j in jobs if j["name"] == "CI / Test (Angular)")
        angular["conclusion"] = "failure"
        next(s for s in angular["steps"] if s["name"] == "Execute Angular Jest Suite")["conclusion"] = "failure"
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_a_failed_job_with_no_failed_or_cancelled_step_is_not_infra(self):
        jobs, annotations = scenario(RESTARTED)
        for step in dotnet(jobs)["steps"]:
            step["conclusion"] = "success"
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_a_failed_job_without_labels_is_not_considered(self):
        jobs, annotations = scenario(RESTARTED)
        dotnet(jobs).update(labels=None, runner_name=None)
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_a_failed_job_without_steps_is_not_infra(self):
        jobs, annotations = scenario(RESTARTED)
        dotnet(jobs)["steps"] = None
        self.assertIsNone(runner_route.infra_fingerprint(jobs, {}))

    def test_a_cancelled_run_is_not_infra(self):
        jobs, annotations = scenario(RESTARTED)
        dotnet(jobs)["conclusion"] = "cancelled"
        self.assertIsNone(runner_route.infra_fingerprint(jobs, annotations))

    def test_fingerprint_is_one_bounded_line(self):
        jobs, annotations = scenario(RESTARTED)
        dotnet(jobs)["name"] = "CI / Build\nhosted=true" + "x" * 500
        found = runner_route.infra_fingerprint(jobs, annotations)
        self.assertNotIn("\n", found)
        self.assertLessEqual(len(found), runner_route.MAX_TEXT)


class DecideTests(unittest.TestCase):
    def decide(self, **overrides):
        args = dict(forced_hosted=False, token_present=True, http_status=200, runners=runners(), previous_fingerprint="", previous_error="")
        args.update(overrides)
        return runner_route.decide(**args)

    def test_online_runners_route_to_proxmox_with_the_count(self):
        hosted, reason = self.decide()
        self.assertFalse(hosted)
        self.assertIn("3 of 3", reason)
        self.assertIn("HTTP 200", reason)

    def test_busy_runners_still_route_to_proxmox(self):
        doc = runners()
        for runner in doc["runners"]:
            runner["busy"] = True
        self.assertFalse(self.decide(runners=doc)[0])

    def test_no_online_runner_routes_hosted(self):
        doc = runners()
        for runner in doc["runners"]:
            runner["status"] = "offline"
        hosted, reason = self.decide(runners=doc)
        self.assertTrue(hosted)
        self.assertIn("no Proxmox runner online", reason)

    def test_online_runners_without_the_proxmox_label_do_not_count(self):
        doc = runners()
        for runner in doc["runners"]:
            runner["labels"] = [label for label in runner["labels"] if label["name"] != "proxmox"]
        self.assertTrue(self.decide(runners=doc)[0])

    def test_malformed_runner_entries_are_skipped(self):
        doc = runners()
        doc["runners"] = ["not a runner", {"status": "online", "labels": None}, doc["runners"][0]]
        hosted, reason = self.decide(runners=doc)
        self.assertFalse(hosted)
        self.assertIn("1 of 1", reason)

    def test_forced_hosted_wins(self):
        hosted, reason = self.decide(forced_hosted=True)
        self.assertTrue(hosted)
        self.assertIn("forced", reason)

    def test_an_infra_failure_in_the_previous_attempt_routes_hosted(self):
        hosted, reason = self.decide(previous_fingerprint="job lost its runner")
        self.assertTrue(hosted)
        self.assertIn("job lost its runner", reason)

    def test_without_a_token_the_variable_decides(self):
        hosted, reason = self.decide(token_present=False, http_status=0, runners=None)
        self.assertFalse(hosted)
        self.assertIn("RUNNER_STATUS_TOKEN", reason)

    def test_an_api_error_falls_back_to_the_variable_and_names_the_status(self):
        for status in (0, 401, 403, 404, 500):
            with self.subTest(status=status):
                hosted, reason = self.decide(http_status=status, runners=None)
                self.assertFalse(hosted)
                self.assertIn(f"HTTP {status}", reason)

    def test_an_unreadable_document_falls_back_to_the_variable(self):
        for doc in (None, {}, {"runners": "x"}, [1]):
            with self.subTest(doc=doc):
                self.assertFalse(self.decide(runners=doc)[0])

    def test_an_unreadable_previous_attempt_is_noted_and_the_health_check_decides(self):
        hosted, reason = self.decide(previous_error="previous attempt jobs HTTP 404")
        self.assertFalse(hosted)
        self.assertIn("previous attempt jobs HTTP 404", reason)


class VerdictTests(unittest.TestCase):
    def verdict(self, **overrides):
        args = dict(attempt=1, conclusion="failure", proxmox=True, fingerprint="", error="", previous_fingerprint="")
        args.update(overrides)
        return runner_route.verdict(**args)

    def test_an_infra_failure_on_attempt_one_is_retried_once(self):
        retry, note = self.verdict(fingerprint="job lost its runner")
        self.assertTrue(retry)
        self.assertIn("job lost its runner", note)
        self.assertIn("GitHub-hosted", note)

    def test_a_test_failure_is_never_retried_and_the_note_says_why(self):
        retry, note = self.verdict()
        self.assertFalse(retry)
        self.assertIn("Not retried", note)
        self.assertIn("code or the tests", note)

    def test_a_later_attempt_is_never_retried_again(self):
        retry, note = self.verdict(attempt=2, fingerprint="job lost its runner")
        self.assertFalse(retry)
        self.assertIn("only attempt 1", note)

    def test_the_retried_attempt_names_the_first_failure_and_where_it_ran(self):
        for proxmox, where in ((False, "GitHub-hosted"), (True, "the Proxmox runner")):
            with self.subTest(proxmox=proxmox):
                retry, note = self.verdict(attempt=2, conclusion="success", proxmox=proxmox, previous_fingerprint="job lost its runner")
                self.assertFalse(retry)
                self.assertEqual(note, f"Attempt 1 failed on the Proxmox runner (job lost its runner); this attempt ran on {where}.")

    def test_success_cancel_and_hosted_failures_get_no_note(self):
        for overrides in ({"conclusion": "success"}, {"conclusion": "cancelled"}, {"proxmox": False, "fingerprint": "x"}):
            with self.subTest(**overrides):
                self.assertEqual(self.verdict(**overrides), (False, ""))

    def test_an_unclassified_failure_is_not_retried_and_says_so(self):
        retry, note = self.verdict(error="jobs of attempt 1 returned HTTP 500", fingerprint="x")
        self.assertFalse(retry)
        self.assertIn("could not be classified (jobs of attempt 1 returned HTTP 500)", note)

    def test_the_note_is_one_line(self):
        _, note = self.verdict(fingerprint="a\nretry=true")
        self.assertNotIn("\n", note)


class CliTests(unittest.TestCase):
    def run_cli(self, argv):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(runner_route.main(argv), 0)
        return dict(line.split("=", 1) for line in out.getvalue().splitlines())

    def test_classify_prints_the_fingerprint_of_the_restarted_runner(self):
        with tempfile.TemporaryDirectory() as d:
            out = self.run_cli(["classify"] + unpacked(RESTARTED, Path(d)))
        self.assertEqual(out["infra"], "true")
        self.assertEqual(out["proxmox"], "true")
        self.assertIn(CANCELLED_STEP, out["fingerprint"])

    def test_classify_a_test_failure(self):
        with tempfile.TemporaryDirectory() as d:
            out = self.run_cli(["classify"] + unpacked(TEST_FAILURE, Path(d)))
        self.assertEqual(out, {"infra": "false", "fingerprint": "", "proxmox": "true"})

    def test_classify_with_missing_inputs_is_not_infra(self):
        with tempfile.TemporaryDirectory() as d:
            out = self.run_cli(["classify", "--jobs", str(Path(d) / "absent.json"), "--annotations-dir", str(Path(d) / "absent")])
        self.assertEqual(out, {"infra": "false", "fingerprint": "", "proxmox": "false"})

    def test_classify_a_jobs_file_that_is_not_an_object(self):
        with tempfile.TemporaryDirectory() as d:
            listed = Path(d) / "jobs.json"
            listed.write_text("[]", encoding="utf-8")
            out = self.run_cli(["classify", "--jobs", str(listed), "--annotations-dir", d])
        self.assertEqual(out, {"infra": "false", "fingerprint": "", "proxmox": "false"})

    def test_decide_reads_the_runners_file(self):
        out = self.run_cli(["decide", "--forced-hosted", "false", "--token-present", "true", "--http-status", "200",
                            "--runners", str(FIXTURES / "runners-online.json")])
        self.assertEqual(out["hosted"], "false")
        self.assertIn("3 of 3", out["reason"])

    def test_decide_with_a_broken_runners_file(self):
        with tempfile.TemporaryDirectory() as d:
            broken = Path(d) / "runners.json"
            broken.write_text("{not json", encoding="utf-8")
            out = self.run_cli(["decide", "--forced-hosted", "false", "--token-present", "true", "--http-status", "200", "--runners", str(broken),
                                "--previous-fingerprint", "x\ny", "--previous-error", ""])
        self.assertEqual(out["hosted"], "true")
        self.assertNotIn("\n", out["reason"])

    def test_the_script_entry_point_exits_with_the_command_status(self):
        argv = ["runner_route.py", "decide", "--forced-hosted", "true", "--token-present", "false"]
        with mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()) as out, self.assertRaises(SystemExit) as done:
            runpy.run_path(str(REPO / "scripts" / "ci" / "runner_route.py"), run_name="__main__")
        self.assertEqual(done.exception.code, 0)
        self.assertIn("hosted=true", out.getvalue())

    def test_verdict_prints_retry_and_note(self):
        out = self.run_cli(["verdict", "--attempt", "1", "--conclusion", "failure", "--proxmox", "true", "--fingerprint", "job lost its runner"])
        self.assertEqual(out["retry"], "true")
        self.assertIn("job lost its runner", out["note"])

    def test_verdict_with_a_non_numeric_attempt_is_not_retried(self):
        out = self.run_cli(["verdict", "--attempt", "null", "--conclusion", "failure", "--proxmox", "true", "--fingerprint", "x"])
        self.assertEqual(out["retry"], "false")

    def test_decide_with_a_bad_status_is_an_api_error(self):
        out = self.run_cli(["decide", "--forced-hosted", "false", "--token-present", "true", "--http-status", "000"])
        self.assertEqual(out["hosted"], "false")
        self.assertIn("HTTP 0", out["reason"])


class InputTests(unittest.TestCase):
    def test_classifying_does_not_mutate_the_jobs(self):
        jobs, _ = scenario(RESTARTED)
        before = copy.deepcopy(jobs)
        runner_route.infra_fingerprint(jobs, {})
        self.assertEqual(jobs, before)


if __name__ == "__main__":
    unittest.main()
