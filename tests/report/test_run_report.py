import io
import json
import re
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(REPO / "scripts" / "ci"))

import run_report  # noqa: E402

RUN = {"id": 1, "html_url": "https://example.invalid/run/1", "run_attempt": 1, "head_sha": "abc1234def", "conclusion": "failure",
       "head_repository": {"full_name": "owner/repo"}}
HOSTILE = "```\n@everyone see https://example.invalid\n```"


def fenced_blocks(body):
    blocks, inside, ticks, lines = [], False, "", []
    for line in body.split("\n"):
        if not inside and re.fullmatch(r"(`{3,})text", line):
            inside, ticks, lines = True, line[:-4], []
        elif inside and line == ticks:
            blocks.append("\n".join(lines))
            inside = False
        elif inside:
            lines.append(line)
    return blocks


def outside_fences(body):
    for block in fenced_blocks(body):
        body = body.replace(block, "")
    return body


class ParseTests(unittest.TestCase):
    def test_passing_trx_counts_every_project(self):
        suite = run_report.parse_trx_dir(FIXTURES / "dotnet-passing")
        self.assertEqual((suite.total, suite.passed, suite.failed, suite.skipped), (17, 17, 0, 0))

    def test_failing_trx_counts_the_skip_and_keeps_message_and_stack(self):
        suite = run_report.parse_trx_dir(FIXTURES / "dotnet-failing")
        self.assertEqual((suite.total, suite.passed, suite.failed, suite.skipped), (12, 10, 1, 1))
        failure = suite.failures[0]
        self.assertIn("CalculateTax_RoundsHalfUp", failure.name)
        self.assertIn("Expected: 7.01", failure.message)
        self.assertIn("FixtureFailureTests.cs:line 12", failure.stack)
        self.assertNotIn("System.Reflection", failure.stack)

    def test_jest_failure_has_no_ansi_and_splits_message_from_stack(self):
        suite = run_report.parse_jest(FIXTURES / "jest-failing.json")
        self.assertEqual((suite.total, suite.passed, suite.failed, suite.skipped), (31, 29, 1, 1))
        failure = suite.failures[0]
        self.assertNotIn("\x1b", failure.message + failure.stack)
        self.assertIn('Expected: "expected value"', failure.message)
        self.assertTrue(failure.stack.lstrip().startswith("at "))
        self.assertIn("fixture-failure.spec.ts:13:52", failure.stack)
        self.assertNotIn("node_modules", failure.stack)

    def test_passing_jest(self):
        suite = run_report.parse_jest(FIXTURES / "jest-passing.json")
        self.assertEqual((suite.total, suite.passed, suite.failed, suite.skipped), (29, 29, 0, 0))

    def test_missing_inputs_give_empty_suites(self):
        self.assertEqual(run_report.parse_trx_dir(None).total, 0)
        self.assertEqual(run_report.parse_jest("/nonexistent/jest.json").total, 0)

    def test_oversized_and_broken_files_are_noted_not_parsed(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "big.trx").write_text("x" * 50, encoding="utf-8")
            (Path(d) / "broken.json").write_text("{", encoding="utf-8")
            with mock.patch.object(run_report, "MAX_FILE_BYTES", 10):
                self.assertIn("larger than", run_report.parse_trx_dir(d).notes[0])
            self.assertIn("unreadable", run_report.parse_jest(Path(d) / "broken.json").notes[0])

    def test_trx_without_counters_or_broken_xml_is_noted(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "a.trx").write_text("<TestRun", encoding="utf-8")
            (Path(d) / "b.trx").write_text('<TestRun xmlns="http://microsoft.com/schemas/VisualStudio/TeamTest/2010"/>', encoding="utf-8")
            notes = run_report.parse_trx_dir(d).notes
        self.assertIn("unreadable", notes[0])
        self.assertIn("no result counters", notes[1])

    def test_a_spec_that_fails_to_compile_is_reported_as_a_failed_file(self):
        with tempfile.TemporaryDirectory() as d:
            data = {"numTotalTests": 0, "numPassedTests": 0, "numFailedTests": 0, "numPendingTests": 0, "testResults": [
                {"name": "/w/apps/frontend/src/app/billing/broken.spec.ts", "status": "failed", "assertionResults": [],
                 "message": "\x1b[31mTest suite failed to run\x1b[39m\n\n    src/app/billing/broken.spec.ts:3:7 - error TS2322: Type 'string' is not assignable to type 'number'.\n"}]}
            (Path(d) / "jest.json").write_text(json.dumps(data), encoding="utf-8")
            suite = run_report.parse_jest(Path(d) / "jest.json")
        self.assertEqual(suite.failures[0].name, "broken.spec.ts")
        self.assertIn("error TS2322", suite.failures[0].message)
        self.assertNotIn("\x1b", suite.failures[0].message)

    def test_restore_hits_read_the_client_records_in_a_job_log(self):
        log = ('2026-10-08T07:57:09.7020158Z {"bytes": 71792850, "detail": "", "key": "9f526c135295", "kind": "nuget", "ms": 2674, "op": "restore", "status": "hit"}\n'
               '2026-10-08T07:57:12.3983333Z {"bytes": 0, "detail": "no pointer", "key": "ab0b", "kind": "dotnet-outputs", "ms": 2, "op": "restore", "status": "miss"}\n'
               '2026-10-08T07:57:13.0000000Z {"op": "save", "kind": "nuget", "status": "saved"}\n')
        self.assertEqual(run_report.restore_hits(log), {"nuget": "hit", "dotnet-outputs": "miss"})


class RenderTests(unittest.TestCase):
    def suites(self):
        return [run_report.parse_trx_dir(FIXTURES / "dotnet-failing"), run_report.parse_jest(FIXTURES / "jest-failing.json")]

    def test_pass_rate_is_passed_over_executed(self):
        body = run_report.render(RUN, [], self.suites(), {}, [])
        self.assertIn("| .NET | 10 | 1 | 1 | 90.9% | 11 of 12 (91.7%) |", body)
        self.assertIn("| Angular | 29 | 1 | 1 | 96.7% | 30 of 31 (96.8%) |", body)
        self.assertIn("| **Total** | 39 | 2 | 2 | **95.1%** | 41 of 43 |", body)
        self.assertTrue(body.startswith(run_report.MARKER))

    def test_every_failed_test_is_listed_with_its_message(self):
        body = run_report.render(RUN, [], self.suites(), {}, [])
        self.assertIn("### Failed tests (2)", body)
        self.assertIn("Expected: 7.01", body)
        self.assertIn('Expected: "expected value"', body)

    def test_hostile_text_stays_inside_its_fence_and_mentions_are_neutralized(self):
        suites = [run_report.Suite(".NET", 1, 0, 1, 0, [run_report.Failure(".NET", "@everyone test", HOSTILE, "")])]
        body = run_report.render(RUN, [], suites, {}, [])
        self.assertTrue(any("@everyone see" in block for block in fenced_blocks(body)))
        self.assertIsNone(re.search(r"@\w", outside_fences(body)))

    def test_mutation_fixed_three_backtick_fence_is_caught(self):
        suites = [run_report.Suite(".NET", 1, 0, 1, 0, [run_report.Failure(".NET", "t", HOSTILE, "")])]
        with mock.patch.object(run_report, "fence", lambda text: f"```text\n{text}\n```"):
            body = run_report.render(RUN, [], suites, {}, [])
        self.assertFalse(any("@everyone see" in block for block in fenced_blocks(body)))

    def test_job_failed_before_tests_shows_its_step_and_log_tail(self):
        jobs = [{"id": 7, "name": "CI / Build and Test (.NET)", "conclusion": "failure", "html_url": "https://example.invalid/job/7", "runner_name": "pve01-ci-lxc-runner-1",
                 "steps": [{"name": "Checkout Repository", "conclusion": "success"}, {"name": "Restore NuGet Packages (Locked)", "conclusion": "failure"}]},
                {"id": 8, "name": "CI / Report", "conclusion": "success", "steps": []}]
        with tempfile.TemporaryDirectory() as d:
            lines = "".join(f"2026-10-08T08:00:{i:02d}.0000000Z line {i}\n" for i in range(60))
            (Path(d) / "7.log").write_text(lines + "2026-10-08T08:01:00.0000000Z error NU1004: the lock file is out of date\n", encoding="utf-8")
            suites = [run_report.parse_trx_dir(None), run_report.parse_jest(None)]
            body = run_report.render(RUN, jobs, suites, {}, run_report.failed_jobs(jobs, d, suites))
        self.assertIn("Restore NuGet Packages (Locked)", body)
        self.assertIn("error NU1004: the lock file is out of date", body)
        self.assertNotIn("2026-10-08T08:01:00", body)
        self.assertNotIn("line 5\n", body)
        self.assertIn("| .NET | - | - | - | n/a | no test results |", body)
        self.assertIn("Proxmox runner", body)

    def test_the_aggregating_report_job_is_not_listed_as_a_cause(self):
        jobs = [{"id": 10, "name": "CI / Report", "conclusion": "failure", "steps": [{"name": "Generate Pipeline Summary Report", "conclusion": "failure"}]}]
        self.assertEqual(run_report.failed_jobs(jobs, None, self.suites()), [])

    def test_a_failure_explained_by_tests_gets_no_log_tail(self):
        jobs = [{"id": 9, "name": "CI / Build and Test (.NET)", "conclusion": "failure", "steps": [{"name": "Execute Transitive Affected Tests", "conclusion": "failure"}]}]
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "9.log").write_text("noise\n", encoding="utf-8")
            found = run_report.failed_jobs(jobs, d, self.suites())
        self.assertEqual(found[0]["tail"], "")

    def test_body_stays_under_the_comment_limit(self):
        many = [run_report.Failure(".NET", f"test {i}", "x" * 600, "") for i in range(400)]
        body = run_report.render(RUN, [], [run_report.Suite(".NET", 400, 0, 400, 0, many)], {}, [])
        self.assertLessEqual(len(body), run_report.MAX_BODY_CHARS + 1)
        self.assertIn("Truncated:", body)


class TargetTests(unittest.TestCase):
    def pr(self, number, sha, repo, state="open"):
        return {"number": number, "state": state, "head": {"sha": sha, "repo": {"full_name": repo}}}

    def test_pull_request_must_match_head_sha_and_head_repository(self):
        self.assertEqual(run_report.resolve_pr(RUN, [self.pr(5, "abc1234def", "owner/repo")]), 5)
        self.assertIsNone(run_report.resolve_pr(RUN, [self.pr(5, "abc1234def", "someone/fork")]))
        self.assertIsNone(run_report.resolve_pr(RUN, [self.pr(5, "0000000", "owner/repo")]))
        self.assertIsNone(run_report.resolve_pr(RUN, [self.pr(5, "abc1234def", "owner/repo", "closed")]))

    def test_only_the_bot_comment_with_the_marker_is_updated(self):
        comments = [{"id": 1, "user": {"login": "someone"}, "body": run_report.MARKER},
                    {"id": 2, "user": {"login": "github-actions[bot]"}, "body": "other"},
                    {"id": 3, "user": {"login": "github-actions[bot]"}, "body": run_report.MARKER + "\nold"}]
        self.assertEqual(run_report.find_comment(comments), 3)
        self.assertIsNone(run_report.find_comment(comments[:2]))


class WorkflowBindingTests(unittest.TestCase):
    def test_callback_listens_to_the_pipeline_by_its_exact_name(self):
        name = re.search(r"^name: (.+)$", (REPO / ".github/workflows/sdet-ci.yml").read_text(encoding="utf-8"), re.M).group(1).strip()
        callback = (REPO / ".github/workflows/sdet-callback.yml").read_text(encoding="utf-8")
        self.assertIn(f'workflows: ["{name}"]', callback)

    def test_callback_never_checks_out_the_run_head(self):
        callback = (REPO / ".github/workflows/sdet-callback.yml").read_text(encoding="utf-8")
        self.assertNotIn("head_sha", re.sub(r"(?s)^.*?jobs:", "", callback).split("Checkout")[1].split("- name:")[0])


class CliTests(unittest.TestCase):
    def test_render_command_end_to_end(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.json").write_text(json.dumps(RUN), encoding="utf-8")
            (Path(d) / "jobs.json").write_text(json.dumps({"jobs": []}), encoding="utf-8")
            out = Path(d) / "body.md"
            with mock.patch("sys.stdout", new=open(out, "w", encoding="utf-8")) as handle:
                run_report.main(["render", "--run", str(Path(d) / "run.json"), "--jobs", str(Path(d) / "jobs.json"),
                                 "--dotnet-dir", str(FIXTURES / "dotnet-failing"), "--jest-file", str(FIXTURES / "jest-failing.json")])
                handle.close()
            self.assertIn("### Failed tests (2)", out.read_text(encoding="utf-8"))

    def test_render_command_shows_the_runner_note_neutralized(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.json").write_text(json.dumps(RUN), encoding="utf-8")
            (Path(d) / "jobs.json").write_text(json.dumps({"jobs": []}), encoding="utf-8")
            out = Path(d) / "body.md"
            with mock.patch("sys.stdout", new=open(out, "w", encoding="utf-8")) as handle:
                run_report.main(["render", "--run", str(Path(d) / "run.json"), "--jobs", str(Path(d) / "jobs.json"),
                                 "--note", "Attempt 1 failed on the Proxmox runner (@team); rerun"])
                handle.close()
            body = out.read_text(encoding="utf-8")
        self.assertIn("**Runner:** Attempt 1 failed on the Proxmox runner", body)
        self.assertNotIn("(@team)", body)

    def test_pr_and_comment_commands_print_the_target(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.json").write_text(json.dumps(RUN), encoding="utf-8")
            (Path(d) / "pulls.json").write_text(json.dumps([{"number": 4, "state": "open", "head": {"sha": "abc1234def", "repo": {"full_name": "owner/repo"}}}]), encoding="utf-8")
            (Path(d) / "comments.json").write_text(json.dumps([]), encoding="utf-8")
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                run_report.main(["pr", "--run", str(Path(d) / "run.json"), "--pulls", str(Path(d) / "pulls.json")])
                run_report.main(["comment", "--comments", str(Path(d) / "comments.json")])
            self.assertEqual(out.getvalue().split("\n")[:2], ["4", ""])


TRX_NS = "http://microsoft.com/schemas/VisualStudio/TeamTest/2010"


def trx(counters, results=""):
    return f'<TestRun xmlns="{TRX_NS}"><ResultSummary><Counters {counters}/></ResultSummary><Results>{results}</Results></TestRun>'


class ParseEdgeTests(unittest.TestCase):
    def test_project_frames_after_library_frames_are_kept(self):
        lines = ["Error: boom", "    at Object.<anonymous> (/w/node_modules/jest/run.js:1:1)", "    at src/app/a.spec.ts:3:4"]
        self.assertEqual(run_report.own_frames(lines), "Error: boom\n    at src/app/a.spec.ts:3:4")

    def test_a_trx_path_that_is_not_a_directory_gives_an_empty_suite(self):
        suite = run_report.parse_trx_dir(FIXTURES / "jest-passing.json")
        self.assertEqual((suite.total, suite.notes), (0, []))

    def test_non_numeric_counters_are_ignored(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "a.trx").write_text(trx('total="3" executed="3" passed="n/a" failed="1"'), encoding="utf-8")
            suite = run_report.parse_trx_dir(d)
        self.assertEqual((suite.total, suite.passed, suite.failed, suite.skipped), (3, 0, 1, 0))

    def test_a_failed_result_without_error_info_has_an_empty_message_and_stack(self):
        with tempfile.TemporaryDirectory() as d:
            result = '<UnitTestResult testName="Bare.Test" outcome="Failed"/>'
            (Path(d) / "a.trx").write_text(trx('total="1" executed="1" passed="0" failed="1"', result), encoding="utf-8")
            failure = run_report.parse_trx_dir(d).failures[0]
        self.assertEqual((failure.name, failure.message, failure.stack), ("Bare.Test", "", ""))

    def test_an_oversized_jest_file_is_noted(self):
        with mock.patch.object(run_report, "MAX_FILE_BYTES", 10):
            suite = run_report.parse_jest(FIXTURES / "jest-passing.json")
        self.assertEqual(suite.total, 0)
        self.assertIn("larger than", suite.notes[0])

    def test_failed_assertions_and_files_without_messages_still_count(self):
        data = {"numTotalTests": 1, "numFailedTests": 1, "testResults": [
            {"name": "a.spec.ts", "status": "failed", "assertionResults": [{"fullName": "a works", "status": "failed"}]},
            {"name": "/w/b.spec.ts", "status": "failed", "assertionResults": []}]}
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "jest.json").write_text(json.dumps(data), encoding="utf-8")
            failures = run_report.parse_jest(Path(d) / "jest.json").failures
        self.assertEqual([(f.name, f.message) for f in failures], [("a works", ""), ("b.spec.ts", "the test file failed to run")])

    def test_a_broken_restore_record_is_skipped(self):
        log = '{"op": "restore", "kind": "nuget"\n{"op": "restore", "kind": "node_modules", "status": "hit"}\n'
        self.assertEqual(run_report.restore_hits(log), {"node_modules": "hit"})


class FailedJobEdgeTests(unittest.TestCase):
    def job(self, job_id, name):
        return {"id": job_id, "name": name, "conclusion": "failure", "steps": [{"name": "Set up job", "conclusion": "failure"}]}

    def test_a_job_outside_the_suites_without_logs_is_listed_without_a_tail(self):
        found = run_report.failed_jobs([self.job(1, "CI / Telemetry")], None, [run_report.Suite(".NET")])
        self.assertEqual((found[0]["step"], found[0]["tail"]), ("Set up job", ""))

    def test_a_missing_log_file_leaves_the_tail_empty(self):
        with tempfile.TemporaryDirectory() as d:
            found = run_report.failed_jobs([self.job(2, "CI / Telemetry")], d, [])
        self.assertEqual(found[0]["tail"], "")

    def test_an_oversized_log_is_noted_in_place_of_the_tail(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "3.log").write_text("x" * 50, encoding="utf-8")
            with mock.patch.object(run_report, "MAX_FILE_BYTES", 10):
                found = run_report.failed_jobs([self.job(3, "CI / Telemetry")], d, [])
        self.assertIn("3.log skipped: larger than 10 bytes", found[0]["tail"])


class RenderEdgeTests(unittest.TestCase):
    def test_skipped_jobs_do_not_decide_the_runner_class(self):
        jobs = [{"conclusion": "skipped", "runner_name": "pve01-ci-lxc-runner-1"}, {"conclusion": "success", "runner_name": "GitHub Actions 1"}]
        self.assertEqual(run_report.runner_class(jobs), "GitHub-hosted")

    def test_a_passing_run_shows_cache_hits_and_suite_notes(self):
        run = dict(RUN, conclusion="success")
        noted = run_report.Suite(".NET", notes=["a.trx unreadable: syntax error"])
        body = run_report.render(run, [], [noted, run_report.Suite("Angular", 2, 2)], {"nuget": "hit"}, [])
        self.assertIn("## ✅ SDET CI passed", body)
        self.assertIn("| .NET | 0 | 0 | 0 | n/a | 0 of 0 (n/a) |", body)
        self.assertIn("Cache restore: `nuget` hit", body)
        self.assertIn("- Note: <code>a.trx unreadable: syntax error</code>", body)

    def test_a_failure_without_message_or_stack_says_so(self):
        suites = [run_report.Suite(".NET", 1, 0, 1, 0, [run_report.Failure(".NET", "t", "", "")])]
        self.assertIn("no message recorded", run_report.render(RUN, [], suites, {}, []))

    def test_a_job_without_step_runner_or_tail(self):
        job = {"name": "CI / Telemetry", "step": None, "runner": None, "url": "https://example.invalid/job/1", "tail": ""}
        body = run_report.render(RUN, [], [], {}, [job])
        self.assertIn("failed at step <code>unknown</code> on <code>no runner</code>", body)
        self.assertNotIn("```", body)

    def test_failed_jobs_are_cut_at_the_body_limit(self):
        jobs = [{"name": f"job {i}", "step": "s", "runner": "r", "url": "u", "tail": "y" * 5000} for i in range(30)]
        body = run_report.render(RUN, [], [], {}, jobs)
        self.assertIn("Truncated: more failed jobs are listed on the run page.", body)
        self.assertLessEqual(len(body), run_report.MAX_BODY_CHARS + 1)


class TargetEdgeTests(unittest.TestCase):
    def test_missing_head_fields_never_match(self):
        pulls = [{"number": 1, "state": "open"},
                 {"number": 2, "state": "open", "head": {"sha": "abc1234def"}},
                 {"number": 3, "state": "open", "head": {"sha": "abc1234def", "repo": {"full_name": "owner/repo"}}}]
        self.assertIsNone(run_report.resolve_pr(RUN, pulls[:2]))
        self.assertIsNone(run_report.resolve_pr({k: v for k, v in RUN.items() if k != "head_repository"}, pulls[2:]))

    def test_comments_without_an_author_or_body_are_skipped(self):
        self.assertIsNone(run_report.find_comment([{"id": 1, "body": run_report.MARKER}, {"id": 2, "user": {"login": run_report.BOT_LOGIN}}]))


class CliEdgeTests(unittest.TestCase):
    def test_load_falls_back_when_there_is_no_file(self):
        self.assertEqual(run_report.load(None, {"a": 1}), {"a": 1})
        self.assertEqual(run_report.load("/nonexistent/run.json", []), [])

    def test_pr_without_a_match_prints_nothing_and_a_found_comment_prints_its_id(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.json").write_text(json.dumps(RUN), encoding="utf-8")
            (Path(d) / "pulls.json").write_text("[]", encoding="utf-8")
            comment = [{"id": 77, "user": {"login": run_report.BOT_LOGIN}, "body": run_report.MARKER}]
            (Path(d) / "comments.json").write_text(json.dumps(comment), encoding="utf-8")
            with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
                run_report.main(["pr", "--run", str(Path(d) / "run.json"), "--pulls", str(Path(d) / "pulls.json")])
                run_report.main(["comment", "--comments", str(Path(d) / "comments.json")])
        self.assertEqual(out.getvalue().split("\n")[:2], ["", "77"])

    def render(self, d, logs_dir=None):
        argv = ["render", "--run", str(Path(d) / "run.json"), "--jobs", str(Path(d) / "jobs.json")]
        with mock.patch("sys.stdout", new_callable=io.StringIO) as out:
            run_report.main(argv + (["--logs-dir", logs_dir] if logs_dir else []))
        return out.getvalue()

    def test_render_reads_cache_hits_from_the_job_logs_it_can_read(self):
        jobs = {"jobs": [{"id": 1, "name": "CI / Build and Test (.NET)", "conclusion": "success"},
                         {"id": 2, "name": "CI / Test (Angular)", "conclusion": "success"},
                         {"id": 3, "name": "CI / Telemetry", "conclusion": "success"}]}
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "run.json").write_text(json.dumps(RUN), encoding="utf-8")
            (Path(d) / "jobs.json").write_text(json.dumps(jobs), encoding="utf-8")
            logs = Path(d) / "logs"
            logs.mkdir()
            (logs / "1.log").write_text('{"op": "restore", "kind": "nuget", "status": "hit"}\n', encoding="utf-8")
            (logs / "2.log").write_text("z" * 500, encoding="utf-8")
            with mock.patch.object(run_report, "MAX_FILE_BYTES", 100):
                with_logs = self.render(d, str(logs))
            without_logs = self.render(d)
        self.assertIn("Cache restore: `nuget` hit", with_logs)
        self.assertNotIn("Cache restore", without_logs)

    def test_the_script_entry_point_exits_with_the_command_status(self):
        argv = ["run_report.py", "comment", "--comments", "/nonexistent/comments.json"]
        with mock.patch.object(sys, "argv", argv), mock.patch("sys.stdout", new_callable=io.StringIO) as out, self.assertRaises(SystemExit) as done:
            runpy.run_path(str(REPO / "scripts" / "ci" / "run_report.py"), run_name="__main__")
        self.assertEqual((done.exception.code, out.getvalue()), (0, "\n"))


if __name__ == "__main__":
    unittest.main()
