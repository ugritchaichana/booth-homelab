#!/usr/bin/env bash
# Exact-set verification of the .NET transitive graph selector; all git writes happen in a disposable clone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECTOR_SH="${SELECTOR_SH:-$REPO_ROOT/scripts/apps/dotnet-affected-test.sh}"
[ -f "$SELECTOR_SH" ] || { echo "Selector script not found: $SELECTOR_SH" >&2; exit 1; }
SELECTOR_SH="$(cd "$(dirname "$SELECTOR_SH")" && pwd)/$(basename "$SELECTOR_SH")"

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

WORK=""
cleanup() {
    case "$WORK" in
        */selector-harness.*) [ -d "$WORK" ] && rm -rf -- "$WORK" ;;
    esac
    return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/selector-harness.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
ROOT_DIR="$WORK/apps/backend"
CHECKOUT="$WORK"

echo "=========================================================="
echo "   Verification: Bash Transitive Graph Engine (exact sets) "
echo "=========================================================="
echo "Source Repository: $REPO_ROOT"
echo "Selector Script:   $SELECTOR_SH"
echo "Disposable Clone:  $WORK"

git clone --quiet --no-hardlinks "$REPO_ROOT" "$WORK"
git -C "$WORK" config user.name "Harness Test Runner"
git -C "$WORK" config user.email "harness@booth-homelab.local"
git -C "$WORK" config commit.gpgsign false

fail() {
    echo "    [FAIL] $1" >&2
    exit 1
}

fmt_set() {
    if [ -z "$1" ]; then echo "(none)"; else printf '%s\n' "$1" | paste -sd, -; fi
}

OUT=""
run_selector() {
    local rc=0
    OUT="$(cd "$CHECKOUT" && bash "$SELECTOR_SH" "$1" "$2" "$CHECKOUT/apps/backend" "--dry-run" 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "$OUT" >&2
        fail "$LABEL: selector exited with code $rc"
    fi
}

assert_exact_set() {
    local expected actual
    expected="$(printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort)"
    actual="$(printf '%s\n' "$OUT" | tr -d '\r' | sed -n 's/^ *==> \[RUN\] //p' | LC_ALL=C sort)"
    printf '%s\n' "$OUT" | tr -d '\r' | grep -E '==> \[RUN\]' || true
    if [ "$actual" = "$expected" ]; then
        echo "    [PASS] $LABEL: selected exactly {$(fmt_set "$actual")}"
    else
        echo "    expected: {$(fmt_set "$expected")}" >&2
        echo "    actual:   {$(fmt_set "$actual")}" >&2
        fail "$LABEL: selected set differs from the ProjectReference-graph oracle"
    fi
}

assert_message() {
    if printf '%s\n' "$OUT" | grep -qF "$1"; then
        echo "    [PASS] $LABEL: selector reported \"$1\""
    else
        echo "$OUT" >&2
        fail "$LABEL: selector output lacks \"$1\""
    fi
}

BILLING_UNIT="Billing.Api.UnitTests.csproj"
ORDER_UNIT="Order.Api.UnitTests.csproj"
ORDER_INTEGRATION="Order.Api.IntegrationTests.csproj"

LABEL="leaf project"
echo ""
echo ">>> [$LABEL] Committed leaf project: Billing.Api/InvoiceGenerator.cs..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
echo "// Leaf edit trigger" >> "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK" add -- apps/backend/src/Billing.Api/InvoiceGenerator.cs
git -C "$WORK" commit --quiet -m "leaf edit"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_INTEGRATION"

LABEL="root domain propagation"
echo ""
echo ">>> [$LABEL] Committed root domain: Core.Domain/Money.cs (transitive propagation)..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
echo "// Root domain edit trigger" >> "$ROOT_DIR/src/Core.Domain/Money.cs"
git -C "$WORK" add -- apps/backend/src/Core.Domain/Money.cs
git -C "$WORK" commit --quiet -m "domain edit"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$ORDER_UNIT" "$ORDER_INTEGRATION"

LABEL="docs only"
echo ""
echo ">>> [$LABEL] Committed documentation-only file: docs/test-harness-doc.md..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
mkdir -p "$WORK/docs"
echo "# Docs only change" > "$WORK/docs/test-harness-doc.md"
git -C "$WORK" add -- docs/test-harness-doc.md
git -C "$WORK" commit --quiet -m "docs change"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set
assert_message "Documentation-only change detected. Skipping test execution."

LABEL="unmappable change fails closed"
echo ""
echo ">>> [$LABEL] Committed unmappable non-doc: scripts/ci/probe.sh (fail-closed)..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
mkdir -p "$WORK/scripts/ci"
printf '#!/bin/bash\necho probe\n' > "$WORK/scripts/ci/probe.sh"
git -C "$WORK" add -- scripts/ci/probe.sh
git -C "$WORK" commit --quiet -m "probe script non-doc"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_UNIT" "$ORDER_INTEGRATION"
assert_message "Unmappable non-documentation change detected; selecting FULL test suite"

LABEL="shared build config"
echo ""
echo ">>> [$LABEL] Committed shared build config: Directory.Build.props (fail-closed)..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
echo "<!-- Shared build config probe -->" >> "$ROOT_DIR/Directory.Build.props"
git -C "$WORK" add -- apps/backend/Directory.Build.props
git -C "$WORK" commit --quiet -m "Directory.Build.props"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_UNIT" "$ORDER_INTEGRATION"
assert_message "Shared configuration modified; selecting all test suites"

LABEL="commit range"
echo ""
echo ">>> [$LABEL] Two-commit range (Core.Domain, then Billing.Api)..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
echo "// Range test 1" >> "$ROOT_DIR/src/Core.Domain/Money.cs"
git -C "$WORK" add -- apps/backend/src/Core.Domain/Money.cs
git -C "$WORK" commit --quiet -m "range commit 1 touching Core.Domain"
echo "// Range test 2" >> "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK" add -- apps/backend/src/Billing.Api/InvoiceGenerator.cs
git -C "$WORK" commit --quiet -m "range commit 2 touching Billing.Api"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_UNIT" "$ORDER_INTEGRATION"

LABEL="shared config plus mapped project"
echo ""
echo ">>> [$LABEL] One commit: Directory.Build.props plus mappable Billing.Api (shared config widens the set)..."
BASE="$(git -C "$WORK" rev-parse HEAD)"
echo "<!-- Shared build config probe 2 -->" >> "$ROOT_DIR/Directory.Build.props"
echo "// Mixed edit trigger" >> "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK" add -- apps/backend/Directory.Build.props apps/backend/src/Billing.Api/InvoiceGenerator.cs
git -C "$WORK" commit --quiet -m "shared config plus Billing.Api"
run_selector "$BASE" "$(git -C "$WORK" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_UNIT" "$ORDER_INTEGRATION"
assert_message "Shared configuration modified; selecting all test suites"

LABEL="checkout path contains test"
echo ""
echo ">>> [$LABEL] Unmappable non-doc change in a checkout whose path contains 'test' (name-only test filter)..."
CHECKOUT="$WORK/clone-under-test"
git clone --quiet --no-hardlinks "$WORK" "$CHECKOUT"
git -C "$CHECKOUT" config user.name "Harness Test Runner"
git -C "$CHECKOUT" config user.email "harness@booth-homelab.local"
git -C "$CHECKOUT" config commit.gpgsign false
BASE="$(git -C "$CHECKOUT" rev-parse HEAD)"
mkdir -p "$CHECKOUT/scripts/ci"
printf '#!/bin/bash\necho probe two\n' > "$CHECKOUT/scripts/ci/probe-two.sh"
git -C "$CHECKOUT" add -- scripts/ci/probe-two.sh
git -C "$CHECKOUT" commit --quiet -m "probe script in a path containing test"
run_selector "$BASE" "$(git -C "$CHECKOUT" rev-parse HEAD)"
assert_exact_set "$BILLING_UNIT" "$ORDER_UNIT" "$ORDER_INTEGRATION"
assert_message "Directly Modified Projects (3):"
assert_message "Total Transitive Projects Affected: 3"

echo ""
echo "=========================================================="
echo "   ALL SCENARIOS PASSED (EXACT SETS MATCH THE GRAPH)      "
echo "=========================================================="
