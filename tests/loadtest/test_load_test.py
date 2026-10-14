import io
import json
import os
import runpy
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts" / "ci"))
import load_test  # noqa: E402

T0 = "2026-10-14T05:00:00Z"
SELECT_LOG = "2026-10-14T05:00:01.1Z Runner route (attempt 1): Proxmox VE Self-Hosted (LXC) because 3 of 3 Proxmox runners online (HTTP 200)\n"
BUILD_LOG = (
    '2026-10-14T05:00:02.1Z {"kind": "nuget", "op": "restore", "status": "hit"}\n'
    '2026-10-14T05:00:02.2Z {"kind": "dotnet-outputs", "op": "restore", "project": "a", "status": "hit"}\n'
    '2026-10-14T05:00:02.3Z {"kind": "dotnet-outputs", "op": "restore", "project": "b", "status": "miss"}\n'
    '2026-10-14T05:00:02.4Z {"kind": "dotnet-outputs", "op": "save", "status": "saved"}\n'
    "2026-10-14T05:00:02.5Z {not json\n"
    '2026-10-14T05:00:02.6Z {"op": "restore", broken\n'
    "2026-10-14T05:00:03.0Z  [BENCHMARK] Build Time: 4321 ms\n"
    "2026-10-14T05:00:03.1Z  [BENCHMARK] CoreCompile ran in 1 projects and was skipped in 6\n"
)


def job(name, status="completed", conclusion="success", labels=("self-hosted", "proxmox"), job_id=1, runner="pve01-ci-lxc-runner-1",
        created=T0, started="2026-10-14T05:00:10Z", completed="2026-10-14T05:01:10Z"):
    return {"id": job_id, "name": f"CI / {name}", "status": status, "conclusion": conclusion, "labels": list(labels), "runner_name": runner,
            "created_at": created, "started_at": started, "completed_at": completed}


def runner(status="online", busy=False, labels=("self-hosted", "proxmox")):
    return {"status": status, "busy": busy, "labels": [{"name": label} for label in labels]}


class FakeApi:
    def __init__(self, gets, texts=None):
        self.gets, self.texts, self.posts = gets, texts or {}, []

    def get(self, path):
        value = self.gets[path.split("?")[0]]
        return value.pop(0) if isinstance(value, list) else value

    def request(self, path, body=None):
        return self.texts[path]

    def post(self, path, body):
        self.posts.append((path, body))
        return ""


class Clock:
    def __init__(self, start=1_000_000.0):
        self.now = start

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class ParseTests(unittest.TestCase):
    def test_times_and_durations(self):
        self.assertIsNone(load_test.parse_time(None))
        self.assertEqual(load_test.seconds(T0, "2026-10-14T05:00:30Z"), 30)
        self.assertIsNone(load_test.seconds(None, T0))
        self.assertIsNone(load_test.seconds(T0, None))

    def test_routes_cache_records_and_build_numbers_are_read_from_logs(self):
        self.assertEqual(load_test.routes(SELECT_LOG), [{"attempt": 1, "runner": "Proxmox VE Self-Hosted (LXC)", "reason": "3 of 3 Proxmox runners online (HTTP 200)"}])
        self.assertEqual(load_test.cache_records(BUILD_LOG), {"nuget": {"hit": 1, "total": 1}, "dotnet-outputs": {"hit": 1, "total": 2}})
        self.assertEqual(load_test.build_numbers(BUILD_LOG), {"compiled": 1, "reused": 6, "build_ms": 4321})
        self.assertEqual(load_test.build_numbers("no numbers"), {"compiled": None, "reused": None, "build_ms": None})

    def test_plan_entries_are_ref_equals_count_with_an_optional_repository_and_start(self):
        self.assertEqual(load_test.parse_plan(["load/a=6", "x=y=1", "load/a=5:angular@75", "load/a=5:dotnet"]),
                         [{"ref": "load/a", "count": 6, "suites": "all", "offset": 0}, {"ref": "x=y", "count": 1, "suites": "all", "offset": 0},
                          {"ref": "load/a", "count": 5, "suites": "angular", "offset": 75}, {"ref": "load/a", "count": 5, "suites": "dotnet", "offset": 0}])
        for bad in ("=3", "load/a=x", "load/a=0", "load/a", "load/a=2:frontend", "load/a=2:angular@soon"):
            with self.subTest(bad), self.assertRaisesRegex(ValueError, "REF=COUNT"):
                load_test.parse_plan([bad])

    def test_fmt(self):
        self.assertEqual([load_test.fmt(None), load_test.fmt(2.5, " s"), load_test.fmt(3), load_test.fmt("x")], ["n/a", "2.5 s", "3", "x"])


class SampleTests(unittest.TestCase):
    def test_counts_queued_and_running_jobs_by_where_they_run_and_the_online_proxmox_instances(self):
        jobs = [job("A", status="queued"), job("B", status="waiting"), job("C", status="in_progress"),
                job("D", status="queued", labels=("ubuntu-latest",)), job("E", status="in_progress", labels=("ubuntu-latest",)),
                job("F", status="completed"), job("G", status="pending")]
        runners = [runner(busy=True), runner(), runner(status="offline"), runner(labels=("self-hosted", "other"))]
        self.assertEqual(load_test.sample(5.0, jobs, runners),
                         {"t": 5.0, "queued_proxmox": 3, "running_proxmox": 1, "queued_hosted": 1, "running_hosted": 1, "online": 2, "busy": 1})

    def test_peak_is_the_deepest_queue_and_its_share_per_instance(self):
        samples = [{"t": 1, "queued_proxmox": 4, "online": 3}, {"t": 2, "queued_proxmox": 27, "online": 3}, {"t": 3, "queued_proxmox": 27, "online": 2}]
        self.assertEqual(load_test.peak(samples), {"queued_proxmox": 27, "online": 3, "per_instance": 9.0, "at": 2})
        self.assertEqual(load_test.peak([{"t": 1, "queued_proxmox": 5, "online": 0}])["per_instance"], None)
        self.assertEqual(load_test.peak([]), {"queued_proxmox": 0, "online": 0, "per_instance": 0.0, "at": None})


def attempts_for_run():
    first = [job("Select Runner", labels=("ubuntu-latest",), job_id=11), job("Build (.NET)", job_id=12),
             job("Test (.NET unit)", conclusion="failure", job_id=13), job("Test (.NET integration)", conclusion="skipped", job_id=14)]
    second = [job("Select Runner", labels=("ubuntu-latest",), job_id=21), job("Build (.NET)", labels=("ubuntu-latest",), job_id=22, started=None),
              job("Test (Angular)", conclusion="skipped", job_id=23)]
    return {"7/1": first, "7/2": second}


class SummaryTests(unittest.TestCase):
    def report(self):
        runs = [{"id": 7, "html_url": "https://example.invalid/7", "run_attempt": 2, "conclusion": "success", "head_branch": "load/flaky"}]
        logs = {"11": SELECT_LOG, "12": BUILD_LOG, "21": SELECT_LOG.replace("attempt 1): Proxmox VE Self-Hosted (LXC)", "attempt 2): GitHub-hosted")}
        samples = [{"t": 1, "queued_proxmox": 9, "online": 3}]
        return load_test.summarise([{"ref": "load/flaky", "count": 1, "suites": "all"}], runs, attempts_for_run(), logs, samples)

    def test_each_attempt_keeps_its_jobs_route_cache_and_build_numbers(self):
        report = self.report()
        first, second = report["refs"]["load/flaky (dotnet)"][0]["runs"]
        build = first["jobs"][1]
        self.assertEqual((build["queued_s"], build["ran_s"], build["compiled"], build["cache"]["dotnet-outputs"]), (10, 60, 1, {"hit": 1, "total": 2}))
        self.assertNotIn("routes", first["jobs"][2])
        self.assertIsNone(second["jobs"][1]["queued_s"])
        self.assertEqual(report["peak"]["per_instance"], 3.0)

    def test_render_names_the_route_reuse_and_failed_jobs_of_every_attempt(self):
        text = load_test.render(self.report())
        self.assertIn("Plan: 1 x `load/flaky` (all).", text)
        late = dict(self.report(), plan=[{"ref": "load/a", "count": 2, "suites": "angular", "offset": 75}])
        self.assertIn("Plan: 2 x `load/a` (angular, from 75 s).", load_test.render(late))
        self.assertIn("## load/flaky (dotnet)", text)
        self.assertIn("9 Proxmox jobs queued with 3 runner instances online (3 per instance)", text)
        self.assertIn("attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 1/2, CoreCompile 1 compiled / 6 reused, build 4321 ms; failed: Test (.NET unit)", text)
        self.assertIn("attempt 2 on GitHub-hosted: outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none", text)
        self.assertIn("up to 1 of 1 suite jobs and 1 kinds ran at once; two or more kinds overlapped at 0 job starts, all three (.NET unit, .NET integration, Angular) at 0.", text)


def span(name, start, end, labels=("self-hosted", "proxmox")):
    return job(name, labels=labels, started=f"2026-10-14T05:00:{start:02d}Z" if start is not None else None,
               completed=f"2026-10-14T05:00:{end:02d}Z" if end is not None else None)


class RepositoryTests(unittest.TestCase):
    def test_a_run_is_named_by_the_suites_that_ran_in_it(self):
        cases = {
            "dotnet": [job("Build (.NET)"), job("Test (Angular)", conclusion="skipped")],
            "angular": [job("Build (.NET)", conclusion="skipped"), job("Test (Angular)", conclusion="failure")],
            "all": [job("Build (.NET)"), job("Test (Angular)")],
        }
        for expected, jobs in cases.items():
            with self.subTest(expected):
                self.assertEqual(load_test.repository_of([load_test.job_record(j, {}) for j in jobs]), expected)
        self.assertEqual(load_test.repository_of([load_test.job_record(job("Select Runner", conclusion=None), {})]), "all")


class ConcurrencyTests(unittest.TestCase):
    def measure(self, jobs):
        records = [load_test.job_record(j, {}) for j in jobs]
        return load_test.concurrency({"ref": [{"runs": [{"attempt": 1, "jobs": records}]}]})

    def test_only_proxmox_suite_jobs_with_both_times_count(self):
        jobs = [span("Test (.NET unit)", 0, 30), span("Test (.NET integration)", 10, 40), span("Test (Angular)", 20, 50),
                span("Test (.NET unit)", 45, 55), span("Build (.NET)", 0, 59), span("Test (Angular)", 5, 59, labels=("ubuntu-latest",)),
                span("Test (.NET unit)", None, None), span("Test (.NET integration)", 12, None)]
        self.assertEqual(self.measure(jobs), {"suite_jobs": 4, "most_at_once": 3, "most_kinds_at_once": 3, "moments_mixed": 3, "moments_all_three": 1})

    def test_suites_that_never_overlap_are_never_all_three_at_once(self):
        jobs = [span("Test (.NET unit)", 0, 10), span("Test (.NET integration)", 10, 20), span("Test (Angular)", 20, 30)]
        self.assertEqual(self.measure(jobs), {"suite_jobs": 3, "most_at_once": 1, "most_kinds_at_once": 1, "moments_mixed": 0, "moments_all_three": 0})

    def test_an_attempt_without_a_route_log_says_so(self):
        line = load_test.attempt_line({"attempt": 1, "jobs": [load_test.job_record(job("Test (Angular)"), {})]})
        self.assertTrue(line.startswith("attempt 1 on unknown runner: outputs n/a"))


class WatchTests(unittest.TestCase):
    PLAN = [{"ref": "load/a", "count": 2, "suites": "all"}]

    def api(self, run_lists):
        return FakeApi({
            "/actions/workflows/sdet-ci.yml/runs": [{"workflow_runs": runs} for runs in run_lists],
            "/actions/runs/1/jobs": {"jobs": [job("Build (.NET)", status="queued")]},
            "/actions/runs/2/jobs": {"jobs": [job("Build (.NET)", status="in_progress")]},
            "/actions/runners": {"runners": [runner(), runner(busy=True)]},
        })

    def test_waits_for_every_run_and_a_quiet_period_and_resets_when_a_retry_reopens_a_run(self):
        open1 = {"id": 1, "status": "queued", "head_branch": "load/a"}
        open2 = {"id": 2, "status": "in_progress", "head_branch": "load/a"}
        done1 = {"id": 1, "status": "completed", "head_branch": "load/a"}
        done2 = {"id": 2, "status": "completed", "head_branch": "load/a"}
        other = {"id": 3, "status": "queued", "head_branch": "someone-else"}
        lists = [[open1, other], [open1, open2], [done1, done2], [done1, open2], [done1, done2], [done1, done2], [done1, done2]]
        clock = Clock()
        runs, samples = load_test.watch(self.api(lists), self.PLAN, T0, clock, clock.sleep, interval=10, quiet=20, timeout=600)
        self.assertEqual([r["id"] for r in runs], [1, 2])
        self.assertEqual(len(samples), 7)
        self.assertEqual((samples[1]["queued_proxmox"], samples[1]["running_proxmox"], samples[1]["busy"]), (1, 1, 1))

    def test_gives_up_after_the_timeout(self):
        open1 = {"id": 1, "status": "queued", "head_branch": "load/a"}
        clock = Clock()
        with self.assertRaisesRegex(TimeoutError, "1 of 1 runs still open"):
            load_test.watch(self.api([[open1]] * 10), self.PLAN, T0, clock, clock.sleep, interval=10, quiet=20, timeout=25)


class RunTests(unittest.TestCase):
    def test_dispatches_the_plan_watches_and_collects_logs_of_the_jobs_that_ran(self):
        runs = [{"id": 7, "status": "completed", "head_branch": "load/flaky", "run_attempt": 2, "conclusion": "success", "html_url": "u"}]
        attempts = attempts_for_run()
        api = FakeApi({
            "/actions/workflows/sdet-ci.yml/runs": {"workflow_runs": runs},
            "/actions/runners": {"runners": []},
            "/actions/runs/7/attempts/1/jobs": {"jobs": attempts["7/1"]},
            "/actions/runs/7/attempts/2/jobs": {"jobs": attempts["7/2"]},
        }, {"/actions/jobs/11/logs": SELECT_LOG, "/actions/jobs/12/logs": BUILD_LOG, "/actions/jobs/21/logs": SELECT_LOG, "/actions/jobs/22/logs": ""})
        clock = Clock()
        report = load_test.run(api, [{"ref": "load/flaky", "count": 1, "suites": "dotnet"}], clock, clock.sleep, interval=10, quiet=10)
        self.assertEqual(api.posts, [("/actions/workflows/sdet-ci.yml/dispatches", {"ref": "load/flaky", "inputs": {"force_ubuntu_runner": "false", "suites": "dotnet"}})])
        self.assertEqual(report["refs"]["load/flaky (dotnet)"][0]["attempts"], 2)
        self.assertEqual(report["refs"]["load/flaky (dotnet)"][0]["runs"][0]["jobs"][1]["build_ms"], 4321)


class DispatchOrderTests(unittest.TestCase):
    def test_dispatches_follow_each_entrys_start_and_spacing_and_ties_keep_plan_order(self):
        plan = [{"ref": "a", "count": 3, "suites": "angular", "offset": 20}, {"ref": "b", "count": 1, "suites": "dotnet"}, {"ref": "c", "count": 2, "suites": "dotnet", "offset": 0}]
        self.assertEqual([(at, e["ref"]) for at, e in load_test.schedule(plan, 10)], [(0, "b"), (0, "c"), (10, "c"), (20, "a"), (30, "a"), (40, "a")])

    def test_spacing_pauses_between_dispatches_but_not_before_the_first(self):
        api = FakeApi({"/actions/workflows/sdet-ci.yml/runs": {"workflow_runs": []}, "/actions/runners": {"runners": []}})
        clock, pauses = Clock(), []

        def pause(seconds):
            pauses.append(seconds)
            clock.sleep(seconds)
            if len(api.posts) == 3:
                raise StopIteration

        plan = [{"ref": "a", "count": 2, "suites": "angular"}, {"ref": "b", "count": 1, "suites": "dotnet"}]
        with self.assertRaises(StopIteration):
            load_test.run(api, plan, clock, pause, spacing=7, interval=10, quiet=10)
        self.assertEqual([body["inputs"]["suites"] for _, body in api.posts], ["angular", "dotnet", "angular"])
        self.assertEqual(pauses, [7, 10])

    def test_without_spacing_every_dispatch_goes_out_before_the_first_pause(self):
        api = FakeApi({"/actions/workflows/sdet-ci.yml/runs": {"workflow_runs": []}, "/actions/runners": {"runners": []}})
        seen = []

        def pause(seconds):
            seen.append((seconds, len(api.posts)))
            raise StopIteration

        with self.assertRaises(StopIteration):
            load_test.run(api, [{"ref": "a", "count": 2, "suites": "all"}], Clock(), pause, interval=10, quiet=10)
        self.assertEqual(seen, [(10, 2)])


class Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class ApiTests(unittest.TestCase):
    def test_get_and_post_send_the_token_only_to_the_api_host_and_parse_json(self):
        seen = []

        def opener(request, timeout):
            seen.append((request.full_url, request.get_method(), request.data, request.unredirected_hdrs.get("Authorization"), request.headers.get("Authorization"), timeout))
            return Response(b'{"ok": 1}')

        api = load_test.Api("owner/repo", "secret-token", opener)
        self.assertEqual(api.get("/actions/runners"), {"ok": 1})
        self.assertEqual(api.post("/x", {"a": 1}), '{"ok": 1}')
        self.assertEqual(seen[0], ("https://api.github.com/repos/owner/repo/actions/runners", "GET", None, "Bearer secret-token", None, 60))
        self.assertEqual(seen[1][1:3], ("POST", b'{"a": 1}'))


class MainTests(unittest.TestCase):
    def test_the_script_entry_point_runs_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / "report.json"
            data.write_text(json.dumps(SummaryTests().report()), encoding="utf-8")
            argv = ["load_test.py", "render", "--data", str(data)]
            with mock.patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()) as out, self.assertRaises(SystemExit) as done:
                runpy.run_path(load_test.__file__, run_name="__main__")
        self.assertEqual(done.exception.code, 0)
        self.assertIn("# Load test", out.getvalue())

    def test_render_prints_a_saved_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / "report.json"
            data.write_text(json.dumps(SummaryTests().report()), encoding="utf-8")
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(load_test.main(["render", "--data", str(data)]), 0)
        self.assertIn("## load/flaky (dotnet)", out.getvalue())

    def test_run_needs_a_token_and_writes_the_report(self):
        args = ["run", "--repository", "owner/repo", "--plan", "load/a=1", "--interval", "1", "--quiet", "0"]
        with mock.patch.dict(os.environ, {"GH_TOKEN": ""}), redirect_stdout(io.StringIO()), mock.patch("sys.stderr", io.StringIO()):
            with self.assertRaises(SystemExit):
                load_test.main(args + ["--out", "unused.json"])
        report = {"plan": [{"ref": "load/a", "count": 1, "suites": "all"}], "peak": load_test.peak([]), "samples": 0, "concurrency": load_test.concurrency({}), "refs": {}}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {"GH_TOKEN": "t"}), mock.patch.object(load_test, "run", return_value=report) as run:
            out_file = Path(tmp) / "out.json"
            with redirect_stdout(io.StringIO()) as out:
                self.assertEqual(load_test.main(args + ["--out", str(out_file)], api_factory=lambda repo, token: (repo, token)), 0)
            self.assertEqual(json.loads(out_file.read_text(encoding="utf-8"))["plan"], report["plan"])
        self.assertEqual(run.call_args.args[0], ("owner/repo", "t"))
        self.assertEqual(run.call_args.kwargs, {"spacing": 0, "interval": 1, "quiet": 0})
        self.assertIn("Plan: 1 x `load/a` (all).", out.getvalue())


if __name__ == "__main__":
    unittest.main()
