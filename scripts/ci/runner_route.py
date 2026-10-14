"""Route the SDET pipeline by Proxmox runner health, and decide the one retry of a failed run on the other environment."""
import argparse
import json
import re
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

MAX_TEXT = 300
CAUSE_TEXT = 150
NOTE_TEXT = 600
PROXMOX_LABEL = "proxmox"
TIMEOUT = "exceeded the maximum execution time"
RUNNER_LOSS = ("The runner has received a shutdown signal", "lost communication with the server")
SETUP_STEP = "Set up job"
CHECKOUT_PREFIX = "Checkout"
DERIVED_JOBS = ("Report",)
RETRYABLE = ("failure", "timed_out")
OPERATION_CANCELED = "The operation was canceled."
DELIBERATE_CANCEL = ("was canceled by", "Canceling since a higher priority")
SUITE_ROLES = {"dotnet": ("dotnet-unit-auto", "dotnet-integration-auto"), "angular": ("workspace-unit-auto",)}
QUEUED = ("queued", "waiting", "pending")
BUILD_JOB = "Build (.NET)"
BUILD_ROLE = "dotnet-unit-auto"
PROMISED_ROLES = ("dotnet-unit-auto", "dotnet-integration-auto")
HISTORY = 5
GAP_S = 10
DEFAULT_JOB_S = 50
WAIT_S = 750
CEILING = 15


def one_line(text, limit=MAX_TEXT):
    return re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()[:limit]


def is_proxmox(job):
    return PROXMOX_LABEL in (job.get("labels") or [])


def job_fingerprint(job, annotations):
    name = job.get("name", "?")
    if not job.get("runner_name"):
        return True, f'job "{name}" failed with no runner assigned'
    messages = [a.get("message", "") for a in annotations if a.get("annotation_level") == "failure"]
    if any(TIMEOUT in m for m in messages):
        return False, None
    for phrase in RUNNER_LOSS:
        if any(phrase in m for m in messages):
            return True, f'job "{name}": {phrase}'
    steps = job.get("steps") or []
    failed = [s["name"] for s in steps if s.get("conclusion") == "failure"]
    if failed:
        if failed[0] == SETUP_STEP or failed[0].startswith(CHECKOUT_PREFIX):
            return True, f'job "{name}" failed while setting up, in step "{failed[0]}"'
        return False, None
    cancelled = [s["name"] for s in steps if s.get("conclusion") == "cancelled"]
    if cancelled:
        return True, f'job "{name}" lost its runner: step "{cancelled[0]}" was cancelled and no step failed'
    return False, None


def infra_fingerprint(jobs, annotations_by_job):
    messages = [a.get("message", "") for annotations in annotations_by_job.values() for a in annotations]
    if any(mark in m for m in messages for mark in DELIBERATE_CANCEL):
        return None
    found = []
    for job in jobs:
        annotations = annotations_by_job.get(job.get("id"), [])
        if job.get("conclusion") not in ("failure", "cancelled") or not is_proxmox(job):
            continue
        if job.get("conclusion") == "cancelled" and not any(a.get("message") == OPERATION_CANCELED for a in annotations):
            continue
        infra, text = job_fingerprint(job, annotations)
        if not infra:
            return None
        found.append(text)
    return one_line(found[0]) if found else None


def needed_roles(suites):
    return SUITE_ROLES.get(suites) or SUITE_ROLES["dotnet"] + SUITE_ROLES["angular"]


def online_by_role(runners, roles):
    listed = runners.get("runners") if isinstance(runners, dict) else None
    if not isinstance(listed, list):
        return None
    labelled = [(r, {str(label.get("name", "")).lower() for label in r.get("labels") or []}) for r in listed if isinstance(r, dict)]
    counts = {}
    for role in roles:
        holders = [r for r, labels in labelled if {PROXMOX_LABEL, role} <= labels]
        counts[role] = (sum(1 for r in holders if r.get("status") == "online"), len(holders))
    return counts


def parse_time(value):
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
    except (TypeError, ValueError):
        return None


def job_labels(job):
    return {str(label).lower() for label in job.get("labels") or []}


def queue_depth(open_jobs, role):
    waiting = sum(1 for j in open_jobs if j.get("status") in QUEUED and role in job_labels(j))
    builds = sum(1 for j in open_jobs if str(j.get("name", "")).endswith(BUILD_JOB) and j.get("status") != "completed" and BUILD_ROLE in job_labels(j))
    return waiting + (builds if role in PROMISED_ROLES else 0)


def job_seconds(done_jobs, role):
    spans = []
    for job in done_jobs:
        start, end = parse_time(job.get("started_at")), parse_time(job.get("completed_at"))
        if role in job_labels(job) and job.get("conclusion") not in (None, "skipped") and start is not None and end is not None:
            spans.append((end, end - start))
    recent = [span for _, span in sorted(spans, reverse=True)[:HISTORY]]
    return round(statistics.median(recent)) + GAP_S if recent else DEFAULT_JOB_S


def ceiling(wait_s, job_s, cap):
    return max(1, min(cap, wait_s // job_s))


def queue_status(open_jobs, done_jobs, roles, wait_s, cap):
    status = {}
    for role in roles:
        seconds = job_seconds(done_jobs, role)
        status[role] = (queue_depth(open_jobs, role), ceiling(wait_s, seconds, cap), seconds)
    return status


def positive_int(text, default):
    return int(text) if str(text).isdigit() and int(text) > 0 else default


def env_name(proxmox):
    return "the Proxmox runner" if proxmox else "GitHub-hosted"


def failure_cause(jobs, annotations_by_job):
    fingerprint = infra_fingerprint(jobs, annotations_by_job)
    if fingerprint:
        return fingerprint
    for conclusion, verb in (("failure", "failed"), ("cancelled", "was cancelled")):
        for job in jobs:
            if job.get("conclusion") != conclusion or str(job.get("name", "")).split(" / ")[-1] in DERIVED_JOBS:
                continue
            steps = [s.get("name", "?") for s in job.get("steps") or [] if s.get("conclusion") == conclusion]
            name = job.get("name", "?")
            return one_line(f'job "{name}" {verb} in step "{steps[0]}"' if steps else f'job "{name}" {verb}')
    return ""


def decide(forced_hosted, token_present, http_status, runners, previous_env="", previous_cause="", previous_error="", suites="all",
           queue_jobs=None, queue_error="", wait_s=WAIT_S, cap=CEILING):
    if forced_hosted:
        return True, "forced to GitHub-hosted by the caller (CI_RUNNER, a fork, or the dispatch input)"
    if previous_env == "proxmox":
        why = f" ({previous_cause})" if previous_cause else ""
        return True, one_line(f"the previous attempt ran on the Proxmox runner{why}, so this rerun switches to GitHub-hosted")
    notes = []
    if previous_env == "hosted":
        notes.append("the previous attempt ran on GitHub-hosted, so this rerun goes to Proxmox if a runner is online")
    if previous_error:
        notes.append(f"{one_line(previous_error)}, so it was not classified")
    note = "".join(f"; {n}" for n in notes)
    if not token_present:
        return False, f"no RUNNER_STATUS_TOKEN, so CI_RUNNER decides{note}"
    roles = needed_roles(suites)
    counts = online_by_role(runners, roles) if http_status == 200 else None
    if counts is None:
        return False, f"runner health check failed (HTTP {http_status}), so CI_RUNNER decides{note}"
    tally = ", ".join(f"{role} {online} of {total}" for role, (online, total) in counts.items())
    missing = [role for role, (online, _) in counts.items() if online == 0]
    if missing:
        return True, f"no Proxmox runner online for {', '.join(missing)} (HTTP 200: {tally}){note}"
    online = f"a Proxmox runner online for every role (HTTP 200: {tally})"
    if queue_jobs is None:
        unread = f"; queue not read ({one_line(queue_error, CAUSE_TEXT)}), so no ceiling" if queue_error else ""
        return False, f"{online}{unread}{note}"
    queue = queue_status(*queue_jobs, roles, wait_s, cap)
    load = ", ".join(f"{role} {depth}/{limit} @{seconds}s" for role, (depth, limit, seconds) in queue.items())
    full = [role for role, (depth, limit, _) in queue.items() if depth >= limit]
    if full:
        return True, f"queue full for {', '.join(full)} ({load}){note}"
    return False, f"{online}; queue {load}{note}"


def verdict(attempt, conclusion, proxmox, cause, error, previous_env, previous_cause, infra=False):
    where = "" if error else f" on {env_name(proxmox)}"
    why = one_line(cause or (f"not classified: {error}" if error else "no failed job found"), CAUSE_TEXT)
    failed = conclusion in RETRYABLE or (conclusion == "cancelled" and infra)
    if attempt == 1:
        if not failed:
            return False, ""
        return True, one_line(f"Attempt 1 failed{where} ({why}); the whole run is rerun once, on the other environment unless it must stay on GitHub-hosted.", NOTE_TEXT)
    if attempt < 1 or not (failed or conclusion == "success"):
        return False, ""
    if not previous_env:
        prior = f"attempt {attempt - 1} could not be read"
    elif previous_cause:
        prior = f"attempt {attempt - 1} failed on {env_name(previous_env == 'proxmox')} ({one_line(previous_cause, CAUSE_TEXT)})"
    else:
        prior = f"attempt {attempt - 1} ran on {env_name(previous_env == 'proxmox')} with no failed job"
    if conclusion == "success":
        lead = "Passed on retry" if previous_cause else "Rerun passed"
        return False, one_line(f"{lead}: {prior}; attempt {attempt} passed{where}.", NOTE_TEXT)
    lead = "Failed again" if previous_cause else "Rerun failed"
    return False, one_line(f"{lead}: {prior}; attempt {attempt} failed{where} ({why}). No further retry, so the run is red.", NOTE_TEXT)


def load(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return default


def status_code(text):
    return int(text) if str(text).isdigit() else 0


def jobs_in(directory):
    found = []
    for path in sorted(Path(directory).glob("*.json")):
        doc = load(path, {})
        jobs = doc.get("jobs") if isinstance(doc, dict) else None
        found += [j for j in jobs if isinstance(j, dict)] if isinstance(jobs, list) else []
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    d = sub.add_parser("decide")
    d.add_argument("--forced-hosted", required=True)
    d.add_argument("--token-present", required=True)
    d.add_argument("--http-status", default="0")
    d.add_argument("--runners")
    d.add_argument("--previous-env", default="")
    d.add_argument("--previous-cause", default="")
    d.add_argument("--previous-error", default="")
    d.add_argument("--suites", default="all")
    d.add_argument("--queue-dir")
    d.add_argument("--queue-error", default="")
    d.add_argument("--wait-s", default=str(WAIT_S))
    d.add_argument("--ceiling", default=str(CEILING))
    v = sub.add_parser("verdict")
    v.add_argument("--attempt", required=True)
    v.add_argument("--conclusion", default="")
    v.add_argument("--proxmox", default="false")
    v.add_argument("--cause", default="")
    v.add_argument("--error", default="")
    v.add_argument("--previous-env", default="")
    v.add_argument("--previous-cause", default="")
    v.add_argument("--infra", default="false")
    c = sub.add_parser("classify")
    c.add_argument("--jobs", required=True)
    c.add_argument("--annotations-dir", required=True)
    args = parser.parse_args(argv)
    if args.command == "decide":
        queue_jobs = None
        if args.queue_dir and not args.queue_error:
            opened = jobs_in(Path(args.queue_dir) / "open")
            queue_jobs = (opened, opened + jobs_in(Path(args.queue_dir) / "done"))
        hosted, reason = decide(args.forced_hosted == "true", args.token_present == "true", status_code(args.http_status),
                                load(args.runners, None) if args.runners else None, args.previous_env, args.previous_cause, args.previous_error,
                                args.suites, queue_jobs, args.queue_error, positive_int(args.wait_s, WAIT_S), positive_int(args.ceiling, CEILING))
        print(f"hosted={str(hosted).lower()}")
        print(f"reason={reason}")
    elif args.command == "verdict":
        retry, note = verdict(status_code(args.attempt), args.conclusion, args.proxmox == "true", args.cause, args.error,
                              args.previous_env, args.previous_cause, args.infra == "true")
        print(f"retry={str(retry).lower()}")
        print(f"note={note}")
    else:
        jobs = load(args.jobs, {})
        jobs = jobs.get("jobs", []) if isinstance(jobs, dict) else []
        annotations = {j.get("id"): load(Path(args.annotations_dir) / f"{j.get('id')}.json", []) for j in jobs}
        found = infra_fingerprint(jobs, annotations)
        print(f"infra={'true' if found else 'false'}")
        print(f"fingerprint={found or ''}")
        print(f"proxmox={'true' if any(is_proxmox(j) for j in jobs) else 'false'}")
        print(f"cause={failure_cause(jobs, annotations)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
