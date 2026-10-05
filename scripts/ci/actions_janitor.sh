#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
STALE_MINUTES="${STALE_MINUTES:-30}"
SELF_RUN_ID="${SELF_RUN_ID:-0}"
RUNNER_ADMIN_TOKEN="${RUNNER_ADMIN_TOKEN:-}"
NOW="${NOW_EPOCH:-$(date -u +%s)}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
LOOKBACK_MIN=120
MAX_ACTIVITY_RUNS=40
ALERT_LABEL="ci-runner-offline"
ALERT_TITLE="CI: self-hosted runners offline — queued runs auto-cancelled"

[[ "$STALE_MINUTES" =~ ^[0-9]+$ ]] && (( STALE_MINUTES >= 1 )) || { echo "::error::STALE_MINUTES must be a positive integer, got '$STALE_MINUTES'"; exit 2; }
[[ "$SELF_RUN_ID" =~ ^[0-9]+$ ]] || SELF_RUN_ID=0

DRY=0
if [[ "${DRY_RUN:-false}" == "true" || "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then DRY=1; fi
MODE=$([[ $DRY == 1 ]] && echo dry-run || echo live)

CACHE="$(mktemp -d)"
trap 'rm -rf "$CACHE"' EXIT
FAILS=0

JQ_DEFS='def sh: any((.labels // [])[]; ascii_downcase == "self-hosted");
def ts: if . == null then null else fromdateiso8601 end;
def clean: gsub("[\\r\\n|%]"; " ");'

api_read() { gh api -X GET "$@"; }

api_write() {
  local method="$1" path="$2"
  shift 2
  if (( DRY )); then echo "[dry-run] would ${method} ${path}"; return 0; fi
  if LAST_ERR="$(gh api -X "$method" "$path" "$@" 2>&1)"; then return 0; fi
  return 1
}

since_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

jobs_for() {
  local id="$1" f="$CACHE/jobs-$1.json"
  if [[ ! -f "$f" ]]; then
    api_read "repos/$GH_REPO/actions/runs/$id/jobs" -f filter=latest -f per_page=100 | jq -c '.jobs' > "$f.tmp" && mv "$f.tmp" "$f"
  fi
  cat "$f"
}

list_runs() { api_read "repos/$GH_REPO/actions/runs" -f status="$1" -f per_page=100 | jq -c '.workflow_runs'; }

QUEUED_RUNS="$(list_runs queued)"
ACTIVE_RUNS="$(list_runs in_progress)"
RUNS="$(jq -c --argjson self "$SELF_RUN_ID" -s 'add | unique_by(.id) | map(select(.id != $self))' <<<"$QUEUED_RUNS"$'\n'"$ACTIVE_RUNS")"
N_RUNS="$(jq 'length' <<<"$RUNS")"
: > "$CACHE/decisions.ndjson"

while IFS= read -r run; do
  id="$(jq -r '.id' <<<"$run")"
  if ! jobs="$(jobs_for "$id")"; then
    echo "::warning::could not read jobs of run $id, leaving it alone"
    continue
  fi
  jq -c --argjson run "$run" --argjson now "$NOW" --argjson stale "$STALE_MINUTES" "$JQ_DEFS"'
    [.[] | select(.status == "queued" and sh)] as $q
    | [.[] | select(.status == "queued" and (sh | not))] as $hq
    | [.[] | select(.status == "in_progress")] as $ip
    | [.[] | select(.status != "queued")] as $started
    | [.[] | select(.status == "completed" and .conclusion == "cancelled")] as $cx
    | ([$q[] | $now - (.created_at | ts)] | max // 0) as $qage
    | ($now - ($run.updated_at | ts)) as $idle
    | (($cx | length) > 0 and ($started | all(.status == "completed")) and $idle > $stale * 60) as $force
    | (if ($ip | length) > 0 then ["skip", "has an in-progress job"]
       elif ($hq | length) > 0 then ["skip", "has a queued job on a hosted runner"]
       elif ($q | length) == 0 then ["skip", "no queued self-hosted job"]
       elif $force then ["force", "cancel already requested, queued self-hosted job still pending"]
       elif $qage > $stale * 60 then ["cancel", "self-hosted job queued past the threshold"]
       else ["skip", "self-hosted job queued only \($qage / 60 | floor) min"] end) as $d
    | {id: $run.id,
       name: ($run.name // "run" | clean), event: $run.event, branch: ($run.head_branch // "-" | clean),
       decision: $d[0], reason: $d[1],
       age_min: ((if $force then [$qage, $idle] | max else $qage end) / 60 | floor)}
  ' <<<"$jobs" >> "$CACHE/decisions.ndjson"
done < <(jq -c '.[]' <<<"$RUNS")

N_EXAMINED="$(wc -l < "$CACHE/decisions.ndjson" | tr -d ' ')"
N_CAND="$(jq -s 'map(select(.decision != "skip")) | length' "$CACHE/decisions.ndjson")"

OPEN_ISSUE=""
ISSUE_KNOWN=0
if ISSUES="$(api_read "repos/$GH_REPO/issues" -f labels="$ALERT_LABEL" -f state=open -f per_page=100 2>/dev/null)"; then
  ISSUE_KNOWN=1
  OPEN_ISSUE="$(jq -r '[.[] | select(.pull_request == null) | .number] | first // empty' <<<"$ISSUES")"
else
  echo "::warning::could not list alert issues, issue actions are skipped"
fi

ALIVE=0
STATE=""
METHOD="n/a"
EVIDENCE=""

runners_api() {
  local out
  if ! out="$(GH_TOKEN="$RUNNER_ADMIN_TOKEN" api_read "repos/$GH_REPO/actions/runners" -f per_page=100 2>/dev/null)"; then
    return 1
  fi
  local online total
  online="$(jq -r '[.runners[] | select(.status == "online") | .name] | join(", ")' <<<"$out")"
  total="$(jq -r '.total_count' <<<"$out")"
  METHOD="runners API"
  if [[ -n "$online" ]]; then ALIVE=1; EVIDENCE="online runners: $online"; else EVIDENCE="0 of $total registered runners online"; fi
}

job_activity() {
  local cutoff=$(( NOW - STALE_MINUTES * 60 )) lookback=$(( NOW - LOOKBACK_MIN * 60 )) found="" id jobs checked=0
  METHOD="job activity"
  local ids
  ids="$( { jq -r '.[].id' <<<"$ACTIVE_RUNS"
            api_read "repos/$GH_REPO/actions/runs" -f created=">=$(since_iso "$lookback")" -f per_page=100 \
              | jq -r --argjson cut "$cutoff" --argjson self "$SELF_RUN_ID" "$JQ_DEFS"'
                  .workflow_runs[] | select(.id != $self and ((.updated_at | ts) >= $cut)) | .id'
          } | awk '!seen[$0]++')"
  for id in $ids; do
    (( checked >= MAX_ACTIVITY_RUNS )) && break
    checked=$(( checked + 1 ))
    jobs="$(jobs_for "$id" 2>/dev/null)" || continue
    found="$(jq -r --argjson cut "$cutoff" "$JQ_DEFS"'
      [.[] | select(sh and ((.runner_name // "") != "")
                    and (.status == "in_progress" or ((.started_at | ts) >= $cut) or ((.completed_at | ts) >= $cut)))]
      | first // empty
      | "job \(.id) (\(.status)) on \(.runner_name), \(.completed_at // .started_at), \(.html_url)"' <<<"$jobs")"
    [[ -n "$found" ]] && break
  done
  if [[ -n "$found" ]]; then ALIVE=1; EVIDENCE="$found"; else EVIDENCE="no self-hosted job started, finished or running in the last ${STALE_MINUTES} min (${checked} recent runs checked)"; fi
}

if [[ -n "$RUNNER_ADMIN_TOKEN" ]] && runners_api; then
  :
else
  [[ -z "$RUNNER_ADMIN_TOKEN" ]] || echo "::warning::runners API call failed, falling back to job activity"
  job_activity
fi
if (( ALIVE )); then STATE=ALIVE
elif [[ "$METHOD" == "runners API" ]] || (( N_CAND > 0 )); then STATE=OFFLINE
else STATE=UNKNOWN
fi

{
  echo "## Actions janitor ($MODE)"
  echo
  echo "Runner state: **$STATE** via $METHOD. Evidence: ${EVIDENCE}"
  [[ "$STATE" != UNKNOWN ]] || echo "Nothing is queued past the threshold, so idle runners and offline runners cannot be told apart."
  echo
  echo "Stale threshold: ${STALE_MINUTES} min. Force-cancel is used only when a run already has cancelled jobs, every started job is completed, a self-hosted job is still queued and the run has been idle past the threshold (a job with \`if: always()\` re-queued after a cancel)."
  echo
  echo "| Run | Workflow | Event | Branch | Queued (min) | Decision | Reason |"
  echo "|---|---|---|---|---|---|---|"
} >> "$SUMMARY"

N_ACTED=0
ACTED_LINES=""
while IFS=$'\t' read -r id name event branch age decision reason; do
  outcome="$decision"
  if [[ "$decision" == "skip" ]]; then
    outcome="left alone"
  elif (( ALIVE )); then
    outcome="held (runners alive)"
    echo "::notice::not cancelling run $id ($name, $event $branch) — ${age} min queued but runners are ALIVE"
  else
    endpoint="cancel"; [[ "$decision" == "force" ]] && endpoint="force-cancel"
    verb=$([[ $DRY == 1 ]] && echo "would cancel" || echo "cancelled")
    if api_write POST "repos/$GH_REPO/actions/runs/$id/$endpoint"; then
      echo "::notice::$verb run $id ($name, $event $branch) — ${age} min queued on self-hosted [$endpoint: $reason]"
      outcome="$verb ($endpoint)"
      N_ACTED=$(( N_ACTED + 1 ))
      ACTED_LINES+="- run ${id} | ${name} | ${event} ${branch} | ${age} min queued | ${endpoint}"$'\n'
    else
      outcome="FAILED ($endpoint)"
      FAILS=$(( FAILS + 1 ))
      echo "::warning::${endpoint} of run $id failed: ${LAST_ERR:-unknown error}"
    fi
  fi
  echo "| [$id](https://github.com/$GH_REPO/actions/runs/$id) | $name | $event | $branch | $age | $outcome | $reason |" >> "$SUMMARY"
done < <(jq -r '[.id, .name, .event, .branch, .age_min, .decision, .reason] | @tsv' "$CACHE/decisions.ndjson")

ensure_label() {
  if api_read "repos/$GH_REPO/labels/$ALERT_LABEL" >/dev/null 2>&1; then return 0; fi
  api_write POST "repos/$GH_REPO/labels" -f name="$ALERT_LABEL" -f color=d93f0b \
    -f description="Self-hosted runners offline, janitor cancelled stuck runs" && return 0
  [[ "${LAST_ERR:-}" == *already_exists* ]] && return 0
  echo "::warning::could not create label $ALERT_LABEL: ${LAST_ERR:-unknown error}"
  return 1
}

if (( ISSUE_KNOWN )); then
  stamp="$(since_iso "$NOW")"
  CANCEL_VERB=$([[ $DRY == 1 ]] && echo "would have cancelled" || echo "cancelled")
  if (( ! ALIVE && N_ACTED > 0 )); then
    body="Self-hosted runners looked offline at ${stamp} (${METHOD}: ${EVIDENCE}).
The janitor ${CANCEL_VERB} ${N_ACTED} run(s) queued longer than ${STALE_MINUTES} min:

${ACTED_LINES}
Workflow: https://github.com/${GH_REPO}/actions/workflows/actions-janitor.yml"
    if [[ -n "$OPEN_ISSUE" ]]; then
      echo "::notice::$([[ $DRY == 1 ]] && echo 'would comment' || echo 'commenting') on open alert issue #$OPEN_ISSUE"
      api_write POST "repos/$GH_REPO/issues/$OPEN_ISSUE/comments" -f body="$body" || { FAILS=$(( FAILS + 1 )); echo "::warning::issue comment failed: ${LAST_ERR:-}"; }
    else
      echo "::notice::$([[ $DRY == 1 ]] && echo 'would open' || echo 'opening') alert issue '$ALERT_TITLE'"
      ensure_label || true
      api_write POST "repos/$GH_REPO/issues" -f title="$ALERT_TITLE" -f body="$body" -f "labels[]=$ALERT_LABEL" \
        || { FAILS=$(( FAILS + 1 )); echo "::warning::issue create failed: ${LAST_ERR:-}"; }
    fi
  elif (( ALIVE )) && [[ -n "$OPEN_ISSUE" ]]; then
    echo "::notice::$([[ $DRY == 1 ]] && echo 'would close' || echo 'closing') alert issue #$OPEN_ISSUE, runners are back"
    api_write POST "repos/$GH_REPO/issues/$OPEN_ISSUE/comments" -f body="Runners back online at ${stamp} (${METHOD}). Evidence: ${EVIDENCE}" \
      && api_write PATCH "repos/$GH_REPO/issues/$OPEN_ISSUE" -f state=closed -f state_reason=completed \
      || { FAILS=$(( FAILS + 1 )); echo "::warning::issue close failed: ${LAST_ERR:-}"; }
  fi
fi

echo "janitor tick: mode=$MODE stale=${STALE_MINUTES}m runs_examined=$N_EXAMINED/$N_RUNS candidates=$N_CAND runner_state=$STATE method=$METHOD acted=$N_ACTED failures=$FAILS"
if [[ "$STATE" == "ALIVE" && -z "$OPEN_ISSUE" ]]; then echo "runners ALIVE, no action"; fi
if [[ "$STATE" == "ALIVE" && -n "$OPEN_ISSUE" ]]; then echo "runners ALIVE, no cancellations, alert issue #$OPEN_ISSUE handled"; fi
(( FAILS == 0 ))
