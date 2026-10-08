import io
import json
import re
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


if __name__ == "__main__":
    unittest.main()
