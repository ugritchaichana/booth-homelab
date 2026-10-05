#!/usr/bin/env python3
import datetime
import os
import re
import shutil
import subprocess
import sys

EXPIRY_DAYS = 90
BLOCKING_CAP = 49
CHECK_TIMEOUT_SECONDS = 300
MAX_FAIL_LINES = 10
EVIDENCE_NAME = re.compile(r"^(\d{4}-\d{2}-\d{2})(-ack)?\.md$")
ISO_DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
RECORD_HEADER = re.compile(r"^- Date / Commit:\s*(\d{4}-\d{2}-\d{2})\s*/\s*([0-9a-fA-F]{7,40})\b", re.M)
RECORD_RESULT = re.compile(r"^- Result:\s*score\s*([012])\b", re.M)
RECORD_EXPIRES = re.compile(r"^- Expires:\s*(.*)$", re.M)
CHECK_LINE = re.compile(r"^CHECK \S+ \S+ (PASS|FAIL|INFO)\b")


def run(args, cwd, **kwargs):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kwargs)


def repo_root():
    result = run(["git", "rev-parse", "--show-toplevel"], os.getcwd())
    if result.returncode != 0:
        sys.exit("scorecard: not inside a git work tree")
    return result.stdout.strip()


def today():
    override = os.environ.get("SCORECARD_TODAY")
    return datetime.date.fromisoformat(override) if override else datetime.date.today()


def load_criteria(root):
    rows = []
    with open(os.path.join(root, "standard", "criteria.tsv"), encoding="utf-8") as handle:
        for line in handle.read().splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) != 6:
                sys.exit(f"scorecard: criteria.tsv row needs 6 tab-separated fields: {line[:40]}")
            keys = ("id", "axis", "name", "measured_by", "covered_paths", "check")
            rows.append(dict(zip(keys, fields)))
    return rows


def open_blocking(root):
    path = os.path.join(root, "standard", "blocking.md")
    if not os.path.isfile(path):
        return [("blocking.md missing", "treated as open")]
    rows = []
    with open(path, encoding="utf-8") as handle:
        for line in handle.read().splitlines():
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if not line.lstrip().startswith("|") or len(cells) < 2:
                continue
            if cells[1].lower() == "open":
                rows.append((cells[0], cells[2] if len(cells) > 2 else ""))
    return rows


def evidence_files(root, criterion_id):
    folder = os.path.join(root, "standard", "evidence", criterion_id)
    records, acks = [], []
    if os.path.isdir(folder):
        for name in sorted(os.listdir(folder)):
            match = EVIDENCE_NAME.match(name)
            if match:
                (acks if match.group(2) else records).append((match.group(1), os.path.join(folder, name)))
    return records, acks


def parse_record(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    header, result, expires = RECORD_HEADER.search(text), RECORD_RESULT.search(text), RECORD_EXPIRES.search(text)
    if not (header and result and expires):
        return None
    recorded_on = datetime.date.fromisoformat(header.group(1))
    explicit = ISO_DATE.search(expires.group(1))
    expiry = datetime.date.fromisoformat(explicit.group(0)) if explicit else recorded_on + datetime.timedelta(days=EXPIRY_DAYS)
    return {"date": recorded_on, "sha": header.group(2), "score": int(result.group(1)), "expiry": expiry}


def commit_exists(root, sha):
    return run(["git", "cat-file", "-e", f"{sha}^{{commit}}"], root).returncode == 0


def covered_paths_changed(root, sha, covered_paths):
    if covered_paths == "-":
        return False
    return run(["git", "diff", "--quiet", sha, "HEAD", "--", *covered_paths.split()], root).returncode != 0


def run_check(root, check):
    if check == "-":
        return None
    script = os.path.join("standard", "checks", check)
    if not os.path.isfile(os.path.join(root, script)):
        return {"rc": 2, "lines": [f"CHECK missing script {check}"]}
    try:
        result = run([shutil.which("bash") or "bash", script], root, timeout=CHECK_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        return {"rc": 2, "lines": ["CHECK timeout"]}
    return {"rc": result.returncode, "lines": [line for line in result.stdout.splitlines() if line.startswith("CHECK ")]}


def summarize_check(outcome):
    if outcome is None:
        return "-"
    counts = {"PASS": 0, "FAIL": 0, "INFO": 0}
    for line in outcome["lines"]:
        match = CHECK_LINE.match(line)
        if match:
            counts[match.group(1)] += 1
    verdict = "pass" if outcome["rc"] == 0 else "fail" if outcome["rc"] == 1 else f"error rc={outcome['rc']}"
    return f"{verdict} ({counts['PASS']}P {counts['FAIL']}F {counts['INFO']}I)"


def evaluate(root, criterion, now):
    records, acks = evidence_files(root, criterion["id"])
    outcome = run_check(root, criterion["check"])
    row = {"criterion": criterion, "recorded": None, "current": 0, "state": "none", "check": summarize_check(outcome), "violation": None, "check_lines": outcome["lines"] if outcome and outcome["rc"] != 0 else []}
    if not records:
        return row
    newest_date, newest_path = records[-1]
    record = parse_record(newest_path)
    if record is None:
        row["state"] = "expired: unparseable record"
        row["violation"] = f"{criterion['id']}: newest record {newest_date} is missing Date / Commit, Result or Expires"
        return row
    row["recorded"] = record["score"]
    reasons = []
    if now > record["expiry"]:
        reasons.append(f"date {record['expiry'].isoformat()}")
    if not commit_exists(root, record["sha"]):
        reasons.append("commit missing")
    elif covered_paths_changed(root, record["sha"], criterion["covered_paths"]):
        reasons.append("covered path changed")
    contradicted = outcome is not None and outcome["rc"] != 0
    if reasons:
        row["state"] = "expired: " + ", ".join(reasons)
    elif contradicted:
        row["state"] = "contradicted"
    else:
        row["state"] = "fresh"
        row["current"] = record["score"]
    acknowledged = any(ack_date >= newest_date for ack_date, _ in acks)
    if row["current"] < record["score"] and not acknowledged:
        row["violation"] = f"{criterion['id']}: dropped from {record['score']} to {row['current']} ({row['state']}) with no standard/evidence/{criterion['id']}/<date>-ack.md dated {newest_date} or later"
    return row


def band(composite):
    return "REJECTED" if composite < 50 else "APPROVED WITH CONDITIONS" if composite < 80 else "APPROVED"


def render(rows, blocking, violations, now):
    points = sum(row["current"] for row in rows)
    raw = 2 * points
    composite = min(raw, BLOCKING_CAP) if blocking else raw
    out = [f"## Standard scorecard ({now.isoformat()})", "", "| id | name | recorded | current | state | check |", "|---|---|---|---|---|---|"]
    for row in rows:
        criterion = row["criterion"]
        recorded = "-" if row["recorded"] is None else str(row["recorded"])
        out.append(f"| {criterion['id']} | {criterion['name']} | {recorded} | {row['current']} | {row['state']} | {row['check']} |")
    cap_note = f"cap {BLOCKING_CAP} applied ({len(blocking)} open)" if blocking else "no cap (no open blocking condition)"
    out += ["", f"**Composite: {composite} / 100** - {band(composite)}", f"2 x {points} points = {raw}; {cap_note}.", ""]
    out.append("### Open blocking conditions")
    out += [f"- {name}: {note}" for name, note in blocking] or ["- none"]
    failing = []
    for row in rows:
        lines = [line for line in row["check_lines"] if " FAIL " in line]
        failing += lines if len(lines) <= MAX_FAIL_LINES else lines[:MAX_FAIL_LINES - 1] + lines[-1:]
    if failing:
        out += ["", "### Failing check lines"] + [f"- {line}" for line in failing]
    if violations:
        out += ["", "### Ratchet violations"] + [f"- {message}" for message in violations]
    return "\n".join(out) + "\n"


def main():
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(encoding="utf-8", errors="replace")
    root, now = repo_root(), today()
    rows = [evaluate(root, criterion, now) for criterion in load_criteria(root)]
    violations = [row["violation"] for row in rows if row["violation"]]
    report = render(rows, open_blocking(root), violations, now)
    sys.stdout.write(report)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(report)
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
