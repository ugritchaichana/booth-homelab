#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER_SH="${RUNNER_SH:-$REPO_ROOT/scripts/apps/dotnet-run-tests.sh}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cat > "$work/bin/dotnet" <<'STUB'
#!/usr/bin/env bash
echo "dotnet $*" >> "$CALLS"
case "$2" in *"$FAIL_SUITE"*) [ -n "$FAIL_SUITE" ] && exit 1 ;; esac
exit 0
STUB
chmod +x "$work/bin/dotnet"

built() { mkdir -p "$work/ws/$1/bin/Release/$2" && touch "$work/ws/$1/bin/Release/$2/$(basename "$1").dll"; }
built apps/backend/tests/A.UnitTests net8.0
built apps/backend/tests/B.UnitTests net8.0
built apps/backend/tests/B.UnitTests net9.0
mkdir -p "$work/ws/apps/backend/tests/C.UnitTests"

fails=0
check() {
  local name=$1 list=$2 want_rc=$3 want_calls=$4 fail_suite=${5:-} rc=0
  : > "$work/calls"
  printf '%b' "$list" > "$work/ws/list.txt"
  (cd "$work/ws" && env PATH="$work/bin:$PATH" CALLS="$work/calls" FAIL_SUITE="$fail_suite" bash "$RUNNER_SH" list.txt out) > "$work/out" 2>&1 || rc=$?
  if [ "$rc" -eq "$want_rc" ] && [ "$(cat "$work/calls")" = "$want_calls" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name: rc=$rc calls=[$(cat "$work/calls")] $(tail -3 "$work/out")"
    fails=$((fails + 1))
  fi
}

A="dotnet test apps/backend/tests/A.UnitTests/bin/Release/net8.0/A.UnitTests.dll --logger trx;LogFileName=A.UnitTests.trx --results-directory out"
B="dotnet test apps/backend/tests/B.UnitTests/bin/Release/net8.0/B.UnitTests.dll --logger trx;LogFileName=B.UnitTests.trx --results-directory out"
check "each listed project runs from its built assembly with its own result file" 'apps/backend/tests/A.UnitTests/A.UnitTests.csproj\napps/backend/tests/B.UnitTests/B.UnitTests.csproj\n' 0 "$A
$B"
check "a failing suite fails the step and the next suite still runs" 'apps/backend/tests/A.UnitTests/A.UnitTests.csproj\napps/backend/tests/B.UnitTests/B.UnitTests.csproj\n' 1 "$A
$B" A.UnitTests
check "a project that was not built fails the step and the others still run" 'apps/backend/tests/C.UnitTests/C.UnitTests.csproj\napps/backend/tests/A.UnitTests/A.UnitTests.csproj\n' 1 "$A"
check "windows line endings, blank lines and a missing final newline are read" '\r\napps/backend/tests/A.UnitTests/A.UnitTests.csproj\r\n\napps/backend/tests/B.UnitTests/B.UnitTests.csproj' 0 "$A
$B"
check "an empty list runs nothing and passes" '' 0 ""

rc=0
(cd "$work/ws" && env PATH="$work/bin:$PATH" CALLS="$work/calls" bash "$RUNNER_SH") > "$work/out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && grep -q 'usage: dotnet-run-tests.sh' "$work/out"; then echo "PASS a missing list file argument is refused"; else echo "FAIL missing argument: rc=$rc"; fails=$((fails + 1)); fi

[ "$fails" -eq 0 ] || { echo "$fails failure(s)"; exit 1; }
echo "all test runner cases passed"
