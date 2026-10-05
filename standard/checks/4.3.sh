#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

status=0
require() {
  local requirement="$1" description="$2"
  shift 2
  if "$@"; then
    echo "CHECK 4.3 $requirement PASS $description"
  else
    echo "CHECK 4.3 $requirement FAIL $description"
    status=1
  fi
}

has_files() { [ -n "$(find "$1" -maxdepth 1 -type f 2> /dev/null | head -1)" ]; }
has_docs_dir() { [ -d docs ] || [ -d wiki ]; }
has_checklist() { grep -qE '^[[:space:]]*- \[ \]' .github/pull_request_template.md 2> /dev/null; }
has_owner_rule() { grep -qE '^[^#[:space:]]' .github/CODEOWNERS 2> /dev/null; }

for directory in apps iac scripts .github; do
  require a "directory $directory exists" test -d "$directory"
done
require a "directory docs or wiki exists" has_docs_dir
require b "issue templates exist under .github/ISSUE_TEMPLATE" has_files .github/ISSUE_TEMPLATE
require b ".github/pull_request_template.md has a checklist" has_checklist
require b ".github/CODEOWNERS has an owner rule" has_owner_rule
exit "$status"
