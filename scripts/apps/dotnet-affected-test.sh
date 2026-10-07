#!/usr/bin/env bash
set -euo pipefail

BASE_REF="${1:-HEAD~1}"
HEAD_REF="${2:-HEAD}"
ROOT_DIR="${3:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../apps/backend" && pwd)}"
RESULTS_DIR="${ROOT_DIR}/TestResults"
DRY_RUN="${4:-false}"

# Match the file name only; a checkout path containing "test" must not widen the selection.
find_test_projects() { find "$ROOT_DIR" -iname '*test*.csproj'; }

echo "=========================================================="
echo "   .NET Transitive Dependency Graph Affected Test Runner   "
echo "=========================================================="
echo "Root Directory:    $ROOT_DIR"
echo "Base Reference:    $BASE_REF"
echo "Head Reference:    $HEAD_REF"
echo "Dry Run Mode:      $DRY_RUN"

CHANGED_FILES=$(git diff --name-only "$BASE_REF" "$HEAD_REF" 2>/dev/null || true)
if [ -z "$CHANGED_FILES" ]; then
    echo "==> No committed changes between $BASE_REF and $HEAD_REF. Checking working tree..."
    CHANGED_FILES=$(git diff --name-only || true)
fi

if [ -z "$CHANGED_FILES" ]; then
    echo "[OK] No changes detected. Zero tests required."
    exit 0
fi

echo "==> Step 1: Changed Files Detected:"
echo "$CHANGED_FILES" | sed 's/^/    - /'

DIRECT_PROJECTS=()
while IFS= read -r file; do
    [ -z "$file" ] && continue
    full_path="$(pwd)/$file"
    dir="$(dirname "$full_path")"
    while [[ "$dir" == "$ROOT_DIR"* ]]; do
        csproj=$(find "$dir" -maxdepth 1 -name "*.csproj" -print -quit)
        if [ -n "$csproj" ]; then
            DIRECT_PROJECTS+=("$csproj")
            break
        fi
        [ "$dir" == "$ROOT_DIR" ] && break
        dir="$(dirname "$dir")"
    done
done <<< "$CHANGED_FILES"

readarray -t UNIQUE_DIRECT < <(printf '%s\n' "${DIRECT_PROJECTS[@]:-}" | sort -u | grep -v '^$' || true)

if echo "$CHANGED_FILES" | grep -qE '(^|/)(Directory\.Build\.props|Directory\.Packages\.props|nuget\.config|global\.json)$|\.sln$'; then
    echo "==> [GLOBAL BUILD CONFIG DETECTED] Shared configuration modified; selecting all test suites."
    mapfile -t UNIQUE_DIRECT < <(find_test_projects)
fi

if [ ${#UNIQUE_DIRECT[@]} -eq 0 ]; then
    NON_DOCS=$(echo "$CHANGED_FILES" | grep -vE '\.(md|txt|png|jpg|svg|ico)$|(^|/)(docs|wiki|\.github)/' || true)
    if [ -n "$NON_DOCS" ]; then
        echo "[WARN] Unmappable non-documentation change detected; selecting FULL test suite (fail-closed)."
        mapfile -t UNIQUE_DIRECT < <(find_test_projects)
    else
        echo "[OK] Documentation-only change detected. Skipping test execution."
        exit 0
    fi
fi

echo "==> Step 2: Directly Modified Projects (${#UNIQUE_DIRECT[@]}):"
for p in "${UNIQUE_DIRECT[@]}"; do
    echo "    - $(basename "$p")"
done

mapfile -t ALL_CSPROJ < <(find "$ROOT_DIR" -name "*.csproj")
AFFECTED_ALL=("${UNIQUE_DIRECT[@]}")
QUEUE=("${UNIQUE_DIRECT[@]}")

while [ ${#QUEUE[@]} -gt 0 ]; do
    CURRENT="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    CURRENT_NAME="$(basename "$CURRENT")"

    for candidate in "${ALL_CSPROJ[@]}"; do
        if grep -q "Include=.*${CURRENT_NAME}" "$candidate" 2>/dev/null; then
            ALREADY=0
            for existing in "${AFFECTED_ALL[@]}"; do
                if [ "$existing" == "$candidate" ]; then
                    ALREADY=1
                    break
                fi
            done
            if [ $ALREADY -eq 0 ]; then
                AFFECTED_ALL+=("$candidate")
                QUEUE+=("$candidate")
            fi
        fi
    done
done

AFFECTED_TESTS=()
for proj in "${AFFECTED_ALL[@]}"; do
    if [[ "$(basename "$proj")" =~ Test ]] || grep -q "Microsoft.NET.Test.Sdk" "$proj" 2>/dev/null; then
        AFFECTED_TESTS+=("$proj")
    fi
done

echo "==> Step 3: Transitive Downstream Resolution:"
echo "    Total Transitive Projects Affected: ${#AFFECTED_ALL[@]}"
echo "    Target Test Suites to Execute:       ${#AFFECTED_TESTS[@]}"

if [ ${#AFFECTED_TESTS[@]} -eq 0 ]; then
    echo "[OK] No test projects affected by this changeset. Skipping."
    exit 0
fi

for t in "${AFFECTED_TESTS[@]}"; do
    echo "    ==> [RUN] $(basename "$t")"
done

if [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "--dry-run" ]; then
    echo "[DryRun] Returning affected suites without executing tests."
    exit 0
fi

mkdir -p "$RESULTS_DIR"
for t in "${AFFECTED_TESTS[@]}"; do
    pname="$(basename "$t" .csproj)"
    echo "----------------------------------------------------------"
    echo "  Executing Suite: $pname"
    echo "----------------------------------------------------------"
    dotnet test "$t" \
        --configuration Release \
        -p:Deterministic=true \
        --logger "trx;LogFileName=${pname}.trx" \
        --results-directory "$RESULTS_DIR"
done

echo "=========================================================="
echo "   ALL AFFECTED SUITES PASSED DETERMINISTICALLY!           "
echo "=========================================================="
