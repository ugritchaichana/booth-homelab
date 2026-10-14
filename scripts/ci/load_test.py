#!/usr/bin/env python3
"""Load-test the SDET pipeline: dispatch runs on several refs at once, sample the job queue until every run and its retry
have finished, then summarise routes, retries, queue depth, cache reuse and timings."""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone

API = "https://api.github.com"
WORKFLOW = "sdet-ci.yml"
PROXMOX = "proxmox"
ROUTE = re.compile(r"Runner route \(attempt (\d+)\): (.+?) because (.+)")
COMPILE = re.compile(r"\[BENCHMARK\] CoreCompile ran in (\d+) projects and was skipped in (\d+)")
BUILD_MS = re.compile(r"\[BENCHMARK\] Build Time: (\d+) ms")
TIMESTAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ", re.M)
LOGGED_JOBS = ("Select Runner", "Build (.NET)", "Test (Angular)")
SUITES = ("Test (.NET unit)", "Test (.NET integration)", "Test (Angular)")
REPOSITORIES = ("all", "dotnet", "angular")


class Api:
    def __init__(self, repository, token, opener=urllib.request.urlopen):
        self.base, self.token, self.opener = f"{API}/repos/{repository}", token, opener

    def request(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method="GET" if body is None else "POST")
        req.add_unredirected_header("Authorization", f"Bearer {self.token}")
        req.add_header("Accept", "application/vnd.github+json")
        with self.opener(req, timeout=60) as response:
            return response.read().decode("utf-8", "replace")

    def get(self, path):
        return json.loads(self.request(path))

    def post(self, path, body):
        return self.request(path, body)


def parse_time(value):
    return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp() if value else None


def seconds(start, end):
    first, last = parse_time(start), parse_time(end)
    return None if first is None or last is None else last - first


def on_proxmox(job):
    return PROXMOX in job.get("labels", [])


def sample(now, jobs, runners):
    counts = {f"{state}_{where}": 0 for state in ("queued", "running") for where in ("proxmox", "hosted")}
    for job in jobs:
        state = {"queued": "queued", "waiting": "queued", "pending": "queued", "in_progress": "running"}.get(job.get("status"))
        if state:
            counts[f"{state}_{'proxmox' if on_proxmox(job) else 'hosted'}"] += 1
    online = [r for r in runners if r.get("status") == "online" and PROXMOX in [label.get("name") for label in r.get("labels", [])]]
    return {"t": now, **counts, "online": len(online), "busy": sum(1 for r in online if r.get("busy"))}


def peak(samples):
    if not samples:
        return {"queued_proxmox": 0, "online": 0, "per_instance": 0.0, "at": None}
    top = max(samples, key=lambda s: (s["queued_proxmox"], -s["t"]))
    return {"queued_proxmox": top["queued_proxmox"], "online": top["online"],
            "per_instance": round(top["queued_proxmox"] / top["online"], 2) if top["online"] else None, "at": top["t"]}


def routes(log_text):
    return [{"attempt": int(a), "runner": runner, "reason": reason.strip()} for a, runner, reason in ROUTE.findall(TIMESTAMP.sub("", log_text))]


def cache_records(log_text):
    found = {}
    for line in TIMESTAMP.sub("", log_text).split("\n"):
        line = line.strip()
        if line.startswith("{") and '"op": "restore"' in line:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            tally = found.setdefault(str(record.get("kind")), {"hit": 0, "total": 0})
            tally["total"] += 1
            tally["hit"] += record.get("status") == "hit"
    return found


def build_numbers(log_text):
    text = TIMESTAMP.sub("", log_text)
    compiled, build_ms = COMPILE.search(text), BUILD_MS.search(text)
    return {"compiled": int(compiled.group(1)) if compiled else None, "reused": int(compiled.group(2)) if compiled else None,
            "build_ms": int(build_ms.group(1)) if build_ms else None}


def job_record(job, logs):
    log = logs.get(str(job.get("id")), "")
    record = {"name": job.get("name"), "conclusion": job.get("conclusion"), "runner": job.get("runner_name"),
              "proxmox": on_proxmox(job), "queued_s": seconds(job.get("created_at"), job.get("started_at")),
              "ran_s": seconds(job.get("started_at"), job.get("completed_at")),
              "started": parse_time(job.get("started_at")), "completed": parse_time(job.get("completed_at"))}
    if log:
        record.update({"routes": routes(log), "cache": cache_records(log), **build_numbers(log)})
    return record


def concurrency(by_ref):
    spans = [(j["started"], j["completed"], j["name"].split(" / ")[-1]) for runs in by_ref.values() for run in runs for attempt in run["runs"]
             for j in attempt["jobs"] if j["proxmox"] and j["conclusion"] != "skipped" and j.get("started") and j.get("completed") and j["name"].split(" / ")[-1] in SUITES]
    most, kinds, mixed, moments = 0, 0, 0, 0
    for start, _, _ in spans:
        running = [name for begin, end, name in spans if begin <= start < end]
        most, kinds = max(most, len(running)), max(kinds, len(set(running)))
        mixed += len(set(running)) > 1
        moments += set(SUITES) <= set(running)
    return {"suite_jobs": len(spans), "most_at_once": most, "most_kinds_at_once": kinds, "moments_mixed": mixed, "moments_all_three": moments}


def repository_of(jobs):
    ran = {j["name"].split(" / ")[-1] for j in jobs if j["conclusion"] not in (None, "skipped")}
    build, angular = "Build (.NET)" in ran, "Test (Angular)" in ran
    return "dotnet" if build and not angular else "angular" if angular and not build else "all"


def summarise(plan, runs, attempts, logs, samples):
    by_ref = {}
    for run in runs:
        rows = [{"attempt": n, "jobs": [job_record(j, logs) for j in attempts.get(f"{run['id']}/{n}", [])]} for n in range(1, run["run_attempt"] + 1)]
        group = f"{run['head_branch']} ({repository_of(rows[0]['jobs'])})"
        by_ref.setdefault(group, []).append({"id": run["id"], "url": run.get("html_url"), "attempts": run["run_attempt"],
                                             "conclusion": run.get("conclusion"), "runs": rows})
    return {"plan": plan, "peak": peak(samples), "samples": len(samples), "concurrency": concurrency(by_ref), "refs": by_ref}


def fmt(value, unit=""):
    return "n/a" if value is None else f"{value:g}{unit}" if isinstance(value, (int, float)) else str(value)


def attempt_line(attempt):
    route = next((r for j in attempt["jobs"] for r in j.get("routes", [])), None)
    build = next((j for j in attempt["jobs"] if j["name"].endswith("Build (.NET)")), {})
    cache = build.get("cache", {}).get("dotnet-outputs")
    failed = [j["name"].split(" / ")[-1] for j in attempt["jobs"] if j["conclusion"] in ("failure", "timed_out", "cancelled")]
    where = route["runner"] if route else "unknown runner"
    reuse = f"outputs {cache['hit']}/{cache['total']}" if cache else "outputs n/a"
    compiled = f"CoreCompile {fmt(build.get('compiled'))} compiled / {fmt(build.get('reused'))} reused, build {fmt(build.get('build_ms'), ' ms')}"
    return f"attempt {attempt['attempt']} on {where}: {reuse}, {compiled}; failed: {', '.join(failed) or 'none'}"


def render(report):
    top, spread = report["peak"], report["concurrency"]
    plan = ", ".join("{} x `{}` ({}{})".format(p["count"], p["ref"], p["suites"], f", from {p['offset']} s" if p.get("offset") else "") for p in report["plan"])
    lines = ["# Load test", "", f"Plan: {plan}.",
             f"Peak queue: {top['queued_proxmox']} Proxmox jobs queued with {top['online']} runner instances online "
             f"({fmt(top['per_instance'])} per instance), from {report['samples']} samples.",
             f"Concurrent suites on Proxmox: up to {spread['most_at_once']} of {spread['suite_jobs']} suite jobs and {spread['most_kinds_at_once']} kinds ran at once; "
             f"two or more kinds overlapped at {spread['moments_mixed']} job starts, all three (.NET unit, .NET integration, Angular) at {spread['moments_all_three']}.", ""]
    for ref, runs in sorted(report["refs"].items()):
        lines += [f"## {ref}", ""]
        for run in runs:
            lines.append(f"- [{run['id']}]({run['url']}): {run['conclusion']} after {run['attempts']} attempt(s)")
            lines += [f"  - {attempt_line(a)}" for a in run["runs"]]
        lines.append("")
    return "\n".join(lines)


def matching_runs(api, refs, since):
    found = api.get(f"/actions/workflows/{WORKFLOW}/runs?event=workflow_dispatch&per_page=100&created=%3E%3D{since}")
    return [r for r in found.get("workflow_runs", []) if r.get("head_branch") in refs]


def watch(api, plan, since, clock=time.time, pause=time.sleep, interval=10, quiet=180, timeout=3600):
    refs, expected = {p["ref"] for p in plan}, sum(p["count"] for p in plan)
    samples, settled_at, started = [], None, clock()
    while True:
        runs = matching_runs(api, refs, since)
        open_runs = [r for r in runs if r.get("status") != "completed"]
        jobs = [j for r in open_runs for j in api.get(f"/actions/runs/{r['id']}/jobs?per_page=100").get("jobs", [])]
        samples.append(sample(clock(), jobs, api.get("/actions/runners?per_page=100").get("runners", [])))
        done = len(runs) >= expected and not open_runs
        settled_at = (settled_at or clock()) if done else None
        if done and clock() - settled_at >= quiet:
            return runs, samples
        if clock() - started > timeout:
            raise TimeoutError(f"{len(open_runs)} of {len(runs)} runs still open after {timeout} s")
        pause(interval)


def collect(api, runs):
    attempts, logs = {}, {}
    for run in runs:
        for n in range(1, run["run_attempt"] + 1):
            jobs = api.get(f"/actions/runs/{run['id']}/attempts/{n}/jobs?per_page=100").get("jobs", [])
            attempts[f"{run['id']}/{n}"] = jobs
            for job in jobs:
                if job.get("name", "").split(" / ")[-1] in LOGGED_JOBS and job.get("conclusion") != "skipped":
                    logs[str(job["id"])] = api.request(f"/actions/jobs/{job['id']}/logs")
    return attempts, logs


def parse_plan(values):
    plan = []
    for value in values:
        ref, _, rest = value.rpartition("=")
        rest, _, offset = rest.partition("@")
        count, _, suites = rest.partition(":")
        suites, offset = suites or "all", offset or "0"
        if not ref or not count.isdigit() or int(count) < 1 or suites not in REPOSITORIES or not offset.isdigit():
            raise ValueError(f"expected REF=COUNT[:{'|'.join(REPOSITORIES)}][@SECONDS], got {value!r}")
        plan.append({"ref": ref, "count": int(count), "suites": suites, "offset": int(offset)})
    return plan


def schedule(plan, spacing=0):
    timed = [(entry.get("offset", 0) + i * spacing, n, entry) for n, entry in enumerate(plan) for i in range(entry["count"])]
    return [(at, entry) for at, _, entry in sorted(timed, key=lambda item: item[:2])]


def run(api, plan, clock=time.time, pause=time.sleep, spacing=0, **watch_options):
    since = datetime.fromtimestamp(clock() - 5, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    elapsed = 0
    for at, entry in schedule(plan, spacing):
        if at > elapsed:
            pause(at - elapsed)
            elapsed = at
        api.post(f"/actions/workflows/{WORKFLOW}/dispatches", {"ref": entry["ref"], "inputs": {"force_ubuntu_runner": "false", "suites": entry["suites"]}})
    runs, samples = watch(api, plan, since, clock, pause, **watch_options)
    attempts, logs = collect(api, runs)
    return summarise(plan, runs, attempts, logs, samples)


def main(argv=None, api_factory=Api):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    go = commands.add_parser("run")
    go.add_argument("--repository", required=True)
    go.add_argument("--plan", action="append", required=True, help="REF=COUNT[:SUITES][@SECONDS]; SUITES is all, dotnet or angular, SECONDS delays that entry's first dispatch; repeatable")
    go.add_argument("--out", required=True)
    go.add_argument("--interval", type=int, default=10)
    go.add_argument("--quiet", type=int, default=180)
    go.add_argument("--spacing", type=int, default=0, help="seconds between one entry's dispatches; entries due at the same time go in plan order")
    commands.add_parser("render").add_argument("--data", required=True)
    args = parser.parse_args(argv)
    if args.command == "render":
        with open(args.data, encoding="utf-8") as handle:
            sys.stdout.write(render(json.load(handle)) + "\n")
        return 0
    token = os.environ.get("GH_TOKEN", "")
    if not token:
        parser.error("GH_TOKEN is not set")
    report = run(api_factory(args.repository, token), parse_plan(args.plan), spacing=args.spacing, interval=args.interval, quiet=args.quiet)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=1, sort_keys=True)
    sys.stdout.write(render(report) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
