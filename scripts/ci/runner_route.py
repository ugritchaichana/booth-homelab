"""Route the SDET pipeline by Proxmox runner health and classify a failed attempt as infra or not."""
import argparse
import json
import re
import sys
from pathlib import Path

MAX_TEXT = 300
PROXMOX_LABEL = "proxmox"
TIMEOUT = "exceeded the maximum execution time"
RUNNER_LOSS = ("The runner has received a shutdown signal", "lost communication with the server")
SETUP_STEP = "Set up job"
CHECKOUT_PREFIX = "Checkout"


def one_line(text):
    return re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()[:MAX_TEXT]


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
    found = []
    for job in jobs:
        if job.get("conclusion") != "failure" or not is_proxmox(job):
            continue
        infra, text = job_fingerprint(job, annotations_by_job.get(job.get("id"), []))
        if not infra:
            return None
        found.append(text)
    return one_line(found[0]) if found else None


def online_proxmox(runners):
    listed = runners.get("runners") if isinstance(runners, dict) else None
    if not isinstance(listed, list):
        return None
    proxmox = [r for r in listed if isinstance(r, dict) and PROXMOX_LABEL in {str(label.get("name", "")).lower() for label in r.get("labels") or []}]
    return sum(1 for r in proxmox if r.get("status") == "online"), len(proxmox)


def decide(forced_hosted, token_present, http_status, runners, previous_fingerprint="", previous_error=""):
    if forced_hosted:
        return True, "forced to GitHub-hosted by the caller (CI_RUNNER, a fork, or the dispatch input)"
    if previous_fingerprint:
        return True, one_line(f"the previous attempt failed on the Proxmox runner ({previous_fingerprint})")
    note = f"; {one_line(previous_error)}, so it was not classified" if previous_error else ""
    if not token_present:
        return False, f"no RUNNER_STATUS_TOKEN, so CI_RUNNER decides{note}"
    counts = online_proxmox(runners) if http_status == 200 else None
    if counts is None:
        return False, f"runner health check failed (HTTP {http_status}), so CI_RUNNER decides{note}"
    online, total = counts
    if online == 0:
        return True, f"no Proxmox runner online (HTTP 200, 0 of {total}){note}"
    return False, f"{online} of {total} Proxmox runners online (HTTP 200){note}"


def verdict(attempt, conclusion, proxmox, fingerprint, error, previous_fingerprint):
    if attempt > 1 and previous_fingerprint:
        where = "the Proxmox runner" if proxmox else "GitHub-hosted"
        return False, one_line(f"Attempt {attempt - 1} failed on the Proxmox runner ({previous_fingerprint}); this attempt ran on {where}.")
    if conclusion != "failure":
        return False, ""
    if error:
        return False, one_line(f"Not retried: attempt {attempt} could not be classified ({error}).")
    if not proxmox:
        return False, ""
    if not fingerprint:
        return False, "Not retried: no runner failure was found, so the failure comes from the code or the tests."
    if attempt != 1:
        return False, one_line(f"Not retried: attempt {attempt} failed on the Proxmox runner ({fingerprint}), and only attempt 1 is retried automatically.")
    return True, one_line(f"Attempt 1 failed on the Proxmox runner ({fingerprint}); the whole run is rerun once on GitHub-hosted.")


def load(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError, TypeError):
        return default


def status_code(text):
    return int(text) if str(text).isdigit() else 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    d = sub.add_parser("decide")
    d.add_argument("--forced-hosted", required=True)
    d.add_argument("--token-present", required=True)
    d.add_argument("--http-status", default="0")
    d.add_argument("--runners")
    d.add_argument("--previous-fingerprint", default="")
    d.add_argument("--previous-error", default="")
    v = sub.add_parser("verdict")
    v.add_argument("--attempt", required=True)
    v.add_argument("--conclusion", default="")
    v.add_argument("--proxmox", default="false")
    v.add_argument("--fingerprint", default="")
    v.add_argument("--error", default="")
    v.add_argument("--previous-fingerprint", default="")
    c = sub.add_parser("classify")
    c.add_argument("--jobs", required=True)
    c.add_argument("--annotations-dir", required=True)
    args = parser.parse_args(argv)
    if args.command == "decide":
        hosted, reason = decide(args.forced_hosted == "true", args.token_present == "true", status_code(args.http_status),
                                load(args.runners, None) if args.runners else None, args.previous_fingerprint, args.previous_error)
        print(f"hosted={str(hosted).lower()}")
        print(f"reason={reason}")
    elif args.command == "verdict":
        retry, note = verdict(status_code(args.attempt), args.conclusion, args.proxmox == "true", args.fingerprint, args.error,
                              args.previous_fingerprint)
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
