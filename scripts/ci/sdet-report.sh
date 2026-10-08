#!/usr/bin/env bash
set -euo pipefail
# Runs with a pull-requests write token; everything read from the reported run is untrusted data.
: "${REPOSITORY:?}" "${RUN_ID:?}"
[[ "$RUN_ID" =~ ^[0-9]+$ ]] || { echo "sdet-report: RUN_ID must be a number" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -r -f "$work"' EXIT

gh api "repos/$REPOSITORY/actions/runs/$RUN_ID" > "$work/run.json"
attempt="$(jq -r '.run_attempt' "$work/run.json")"
gh api --paginate "repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$attempt/jobs?per_page=100" | jq -s '{jobs: (map(.jobs) | add)}' > "$work/jobs.json"

mkdir -p "$work/dotnet" "$work/angular" "$work/logs"
gh run download "$RUN_ID" -R "$REPOSITORY" -n sdet-dotnet-test-results -D "$work/dotnet" 2> /dev/null || echo "sdet-report: no .NET test results in run $RUN_ID"
gh run download "$RUN_ID" -R "$REPOSITORY" -n sdet-angular-results -D "$work/angular" 2> /dev/null || echo "sdet-report: no Angular test results in run $RUN_ID"
jq -r '.jobs[] | select(.conclusion != "skipped") | select(.conclusion == "failure" or .conclusion == "timed_out" or (.name | test("NET|Angular"))) | .id' "$work/jobs.json" | tr -d '\r' | while read -r id; do
  url="${GITHUB_API_URL:-https://api.github.com}/repos/$REPOSITORY/actions/jobs/$id/logs"
  if curl -fsSL --max-filesize 50000000 -H "Authorization: Bearer $GH_TOKEN" -o "$work/logs/$id.full" "$url" 2> "$work/logs/$id.err" < /dev/null; then
    tail -c 2000000 "$work/logs/$id.full" > "$work/logs/$id.log"
  else
    echo "sdet-report: no log for job $id: $(head -c 300 "$work/logs/$id.err")"
  fi
  echo "sdet-report: job $id log $(wc -c < "$work/logs/$id.full" 2> /dev/null || echo 0) bytes"
done

python3 "$here/run_report.py" render --run "$work/run.json" --jobs "$work/jobs.json" --dotnet-dir "$work/dotnet" \
  --jest-file "$work/angular/test-results/jest.json" --logs-dir "$work/logs" > "$work/body.md"
cat "$work/body.md" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

gh api --paginate "repos/$REPOSITORY/pulls?state=open&per_page=100" | jq -s 'add' > "$work/pulls.json"
pr="$(python3 "$here/run_report.py" pr --run "$work/run.json" --pulls "$work/pulls.json")"
if [ -z "$pr" ]; then
  echo "sdet-report: no open pull request has head $(jq -r '.head_sha' "$work/run.json"); the report is in the job summary only"
  exit 0
fi
gh api --paginate "repos/$REPOSITORY/issues/$pr/comments?per_page=100" | jq -s 'add' > "$work/comments.json"
comment="$(python3 "$here/run_report.py" comment --comments "$work/comments.json")"
if [ -n "$comment" ]; then
  gh api -X PATCH "repos/$REPOSITORY/issues/comments/$comment" -F "body=@$work/body.md" > /dev/null
  echo "sdet-report: updated comment $comment on #$pr"
else
  gh api "repos/$REPOSITORY/issues/$pr/comments" -F "body=@$work/body.md" > /dev/null
  echo "sdet-report: created the report comment on #$pr"
fi
