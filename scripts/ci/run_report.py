#!/usr/bin/env python3
"""Turn the files of one SDET pipeline run into the pull-request report comment.

Every input may come from a fork: it is parsed as data, capped, and placed in code fences.
"""
import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

MARKER = "<!-- sdet-ci-report -->"
BOT_LOGIN = "github-actions[bot]"
MAX_FILE_BYTES = 5_000_000
MAX_BODY_CHARS = 60_000
MAX_STACK_LINES = 12
MAX_LOG_LINES = 40
TRX = "{http://microsoft.com/schemas/VisualStudio/TeamTest/2010}"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
TIMESTAMP = re.compile(r"^\d{4}-\d\d-\d\dT[\d:.]+Z ", re.M)
SUITE_OF_JOB = {".NET": ".NET", "Angular": "Angular"}
DERIVED_JOBS = ("Report",)
LIBRARY_FRAME = re.compile(r"/node_modules/|node:internal|\(<anonymous>\)|\bat (System|Microsoft|Xunit)\.")


@dataclass
class Failure:
    suite: str
    name: str
    message: str
    stack: str


@dataclass
class Suite:
    name: str
    total: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    failures: list = field(default_factory=list)
    notes: list = field(default_factory=list)

    @property
    def executed(self):
        return self.passed + self.failed


def clean(text):
    return CONTROL.sub("", ANSI.sub("", str(text))).replace("\r\n", "\n").replace("\r", "\n")


def read_capped(path, notes):
    if path.stat().st_size > MAX_FILE_BYTES:
        notes.append(f"{path.name} skipped: larger than {MAX_FILE_BYTES} bytes")
        return None
    return path.read_text(encoding="utf-8-sig", errors="replace")


def own_frames(lines):
    kept = [line for i, line in enumerate(lines) if i == 0 or not LIBRARY_FRAME.search(line)]
    return "\n".join(kept[:MAX_STACK_LINES])


def split_message(text):
    lines = clean(text).strip("\n").split("\n")
    at = next((i for i, line in enumerate(lines) if line.lstrip().startswith("at ")), len(lines))
    return "\n".join(lines[:at]).strip(), own_frames(lines[at:])


def parse_trx_dir(directory):
    suite = Suite(".NET")
    for path in sorted(Path(directory).glob("*.trx")) if directory and Path(directory).is_dir() else []:
        text = read_capped(path, suite.notes)
        if text is None:
            continue
        try:
            root = ET.fromstring(text)
        except ET.ParseError as error:
            suite.notes.append(f"{path.name} unreadable: {error}")
            continue
        counters = root.find(f"{TRX}ResultSummary/{TRX}Counters")
        if counters is None:
            suite.notes.append(f"{path.name} has no result counters")
            continue
        count = {k: int(v) for k, v in counters.attrib.items() if v.isdigit()}
        suite.total += count.get("total", 0)
        suite.passed += count.get("passed", 0)
        suite.failed += sum(count.get(k, 0) for k in ("failed", "error", "timeout", "aborted"))
        suite.skipped += count.get("total", 0) - count.get("executed", 0)
        for result in root.iter(f"{TRX}UnitTestResult"):
            if result.get("outcome") not in ("Failed", "Error", "Timeout", "Aborted"):
                continue
            info = result.find(f"{TRX}Output/{TRX}ErrorInfo")
            if info is None:
                info = ET.Element("ErrorInfo")
            message = clean(info.findtext(f"{TRX}Message", "")).strip()
            stack = clean(info.findtext(f"{TRX}StackTrace", "")).strip("\n").split("\n")
            suite.failures.append(Failure(".NET", result.get("testName", "unnamed test"), message, own_frames(stack)))
    return suite


def parse_jest(path):
    suite = Suite("Angular")
    if not path or not Path(path).is_file():
        return suite
    text = read_capped(Path(path), suite.notes)
    if text is None:
        return suite
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        suite.notes.append(f"{Path(path).name} unreadable: {error}")
        return suite
    suite.total = int(data.get("numTotalTests", 0))
    suite.passed = int(data.get("numPassedTests", 0))
    suite.failed = int(data.get("numFailedTests", 0))
    suite.skipped = int(data.get("numPendingTests", 0)) + int(data.get("numTodoTests", 0))
    for result in data.get("testResults", []):
        for assertion in result.get("assertionResults", []):
            if assertion.get("status") == "failed":
                message, stack = split_message("\n".join(assertion.get("failureMessages") or []))
                suite.failures.append(Failure("Angular", clean(assertion.get("fullName", "unnamed test")), message, stack))
        if result.get("status") == "failed" and not result.get("assertionResults"):
            message, stack = split_message(result.get("message", ""))
            suite.failures.append(Failure("Angular", clean(Path(result.get("name", "test file")).name), message or "the test file failed to run", stack))
    return suite


def restore_hits(log_text):
    hits = {}
    for line in TIMESTAMP.sub("", log_text).split("\n"):
        line = line.strip()
        if line.startswith("{") and '"op": "restore"' in line:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            hits[str(record.get("kind"))] = str(record.get("status"))
    return hits


def failed_jobs(jobs, logs_dir, suites):
    explained = {s.name for s in suites if s.failures}
    found = []
    for job in jobs:
        if job.get("conclusion") not in ("failure", "timed_out") or job.get("name", "").split(" / ")[-1] in DERIVED_JOBS:
            continue
        step = next((s.get("name") for s in job.get("steps", []) if s.get("conclusion") in ("failure", "timed_out")), None)
        suite = next((v for k, v in SUITE_OF_JOB.items() if k in job.get("name", "")), None)
        tail = ""
        log = Path(logs_dir) / f"{job.get('id')}.log" if logs_dir else None
        if suite not in explained and log and log.is_file():
            notes = []
            text = read_capped(log, notes)
            tail = "\n".join(clean(TIMESTAMP.sub("", text)).rstrip("\n").split("\n")[-MAX_LOG_LINES:]) if text else "\n".join(notes)
        found.append({"name": job.get("name", "job"), "step": step, "url": job.get("html_url"), "runner": job.get("runner_name"), "tail": tail})
    return found


def fence(text):
    longest = max((len(m) for m in re.findall(r"`+", text)), default=0)
    ticks = "`" * max(3, longest + 1)
    return f"{ticks}text\n{text}\n{ticks}"


def plain(text):
    return clean(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("@", "@​").replace("\n", " ")


def inline(text):
    return "<code>" + plain(text) + "</code>"


def rate(part, whole):
    return f"{100 * part / whole:.1f}%" if whole else "n/a"


def runner_class(jobs):
    names = {j.get("runner_name") or "" for j in jobs if j.get("conclusion") not in ("skipped", None)}
    return "Proxmox runner" if any(n.startswith("pve") for n in names) else "GitHub-hosted"


def render(run, jobs, suites, hits, failures_jobs, note=""):
    failed_tests = [f for s in suites for f in s.failures]
    ok = run.get("conclusion") == "success"
    attempt = run.get("run_attempt", 1)
    passed = "✅ SDET CI passed" + (f" on attempt {attempt}" if attempt != 1 else "")
    head = [MARKER, f"## {passed if ok else '❌ SDET CI failed'}", ""]
    head.append(f"Run [{run.get('id')}]({run.get('html_url')}) attempt {attempt} on `{str(run.get('head_sha', ''))[:7]}` · "
                f"{runner_class(jobs)} · conclusion `{run.get('conclusion')}`")
    if note:
        head += ["", f"**Runner:** {plain(note)}"]
    head += ["", "| Suite | Passed | Failed | Skipped | Pass rate | Executed |", "|---|---:|---:|---:|---:|---:|"]
    for s in suites:
        if s.total or s.notes:
            head.append(f"| {s.name} | {s.passed} | {s.failed} | {s.skipped} | {rate(s.passed, s.executed)} | {s.executed} of {s.total} ({rate(s.executed, s.total)}) |")
        else:
            head.append(f"| {s.name} | - | - | - | n/a | no test results |")
    total = Suite("Total", sum(s.total for s in suites), sum(s.passed for s in suites), sum(s.failed for s in suites), sum(s.skipped for s in suites))
    head.append(f"| **Total** | {total.passed} | {total.failed} | {total.skipped} | **{rate(total.passed, total.executed)}** | {total.executed} of {total.total} |")
    if hits:
        head += ["", "Cache restore: " + ", ".join(f"`{k}` {v}" for k, v in sorted(hits.items()))]
    notes = [n for s in suites for n in s.notes]
    if notes:
        head += [""] + [f"- Note: {inline(n)}" for n in notes]
    sections = []
    for f in failed_tests:
        body = f.message + ("\n" + f.stack if f.stack else "")
        sections.append(f"<details open><summary>{f.suite}: {inline(f.name)}</summary>\n\n{fence(body or 'no message recorded')}\n</details>")
    job_lines = []
    for j in failures_jobs:
        line = f"- {inline(j['name'])} failed at step {inline(j['step'] or 'unknown')} on {inline(j['runner'] or 'no runner')} · [job log]({j['url']})"
        job_lines.append(line + (f"\n\n{fence(j['tail'])}" if j["tail"] else ""))
    out = "\n".join(head)
    if failed_tests:
        out += f"\n\n### Failed tests ({len(failed_tests)})\n"
    shown = 0
    for section in sections:
        if len(out) + len(section) + 2000 > MAX_BODY_CHARS:
            break
        out += "\n" + section
        shown += 1
    if shown < len(sections):
        out += f"\n\nTruncated: {len(sections) - shown} more failed test(s) are in the run's test results."
    if job_lines:
        out += "\n\n### Failed jobs\n"
        for line in job_lines:
            if len(out) + len(line) + 200 > MAX_BODY_CHARS:
                out += "\n\nTruncated: more failed jobs are listed on the run page."
                break
            out += "\n" + line
    return out[:MAX_BODY_CHARS] + "\n"


def resolve_pr(run, pulls):
    head_repo = (run.get("head_repository") or {}).get("full_name")
    for pr in pulls:
        head = pr.get("head") or {}
        if pr.get("state") == "open" and head.get("sha") == run.get("head_sha") and (head.get("repo") or {}).get("full_name") == head_repo:
            return pr.get("number")
    return None


def find_comment(comments):
    for c in comments:
        if (c.get("user") or {}).get("login") == BOT_LOGIN and MARKER in (c.get("body") or ""):
            return c.get("id")
    return None


def load(path, default):
    return json.loads(Path(path).read_text(encoding="utf-8")) if path and Path(path).is_file() else default


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    r = sub.add_parser("render")
    r.add_argument("--run", required=True)
    r.add_argument("--jobs", required=True)
    r.add_argument("--dotnet-dir")
    r.add_argument("--jest-file")
    r.add_argument("--logs-dir")
    r.add_argument("--note", default="")
    p = sub.add_parser("pr")
    p.add_argument("--run", required=True)
    p.add_argument("--pulls", required=True)
    c = sub.add_parser("comment")
    c.add_argument("--comments", required=True)
    args = parser.parse_args(argv)
    if args.command == "pr":
        number = resolve_pr(load(args.run, {}), load(args.pulls, []))
        print(number or "")
    elif args.command == "comment":
        print(find_comment(load(args.comments, [])) or "")
    else:
        jobs = load(args.jobs, {}).get("jobs", [])
        suites = [parse_trx_dir(args.dotnet_dir), parse_jest(args.jest_file)]
        hits = {}
        for job in jobs:
            log = Path(args.logs_dir) / f"{job.get('id')}.log" if args.logs_dir else None
            if log and log.is_file():
                hits.update(restore_hits(read_capped(log, []) or ""))
        sys.stdout.write(render(load(args.run, {}), jobs, suites, hits, failed_jobs(jobs, args.logs_dir, suites), args.note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
