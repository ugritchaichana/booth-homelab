#!/usr/bin/env bash
# ==============================================================================
# Automated Verification Suite for .NET Transitive Graph Selector (Linux/Bash)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SELECTOR_SH="$REPO_ROOT/scripts/apps/dotnet-affected-test.sh"
ROOT_DIR="$REPO_ROOT/apps/backend"

echo "=========================================================="
echo "   TDD Verification: Bash Transitive Graph Engine         "
echo "=========================================================="
echo "Repository Root: $REPO_ROOT"
echo "Selector Script: $SELECTOR_SH"
echo "Backend Dir:     $ROOT_DIR"

cd "$REPO_ROOT"

ORIGINAL_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)"
ORIGINAL_HEAD="$(git rev-parse HEAD)"
TMP_BRANCH="test-affected-harness-$$"

cleanup() {
    echo "==> Cleaning up harness test artifacts..."
    cd "$REPO_ROOT"
    git checkout "$ORIGINAL_BRANCH" >/dev/null 2>&1 || true
    git branch -D "$TMP_BRANCH" >/dev/null 2>&1 || true
    git checkout "$ORIGINAL_HEAD" -- apps/backend/ 2>/dev/null || true
    git clean -fd apps/backend/ 2>/dev/null || true
    rm -f "$REPO_ROOT/scripts/ci/probe.sh" 2>/dev/null || true
    rm -f "$REPO_ROOT/docs/test-harness-doc.md" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Create isolated test branch
git checkout -b "$TMP_BRANCH" >/dev/null 2>&1

# Scenario 1: Committed Leaf Project Modification (Billing.Api)
echo ""
echo ">>> [SCENARIO 1] Committed Leaf Project: Billing.Api/InvoiceGenerator.cs..."
BASE_1="$(git rev-parse HEAD)"
echo "// Leaf edit trigger" >> "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git add "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git commit -m "test: leaf edit" >/dev/null 2>&1
HEAD_1="$(git rev-parse HEAD)"

OUT_1=$("$SELECTOR_SH" "$BASE_1" "$HEAD_1" "$ROOT_DIR" "--dry-run")
echo "$OUT_1" | grep "==> \[RUN\]" || true

if echo "$OUT_1" | grep -q "Billing.Api.UnitTests.csproj" && ! echo "$OUT_1" | grep -q "Order.Api.UnitTests.csproj"; then
    echo "    [PASS] SCENARIO 1: Only Billing.Api.UnitTests was selected!"
else
    echo "    [FAIL] SCENARIO 1: Expected only Billing.Api.UnitTests.csproj."
    exit 1
fi

# Scenario 2: Committed Root Domain Modification (Core.Domain) -> Transitive Propagation
echo ""
echo ">>> [SCENARIO 2] Committed Root Domain: Core.Domain/Money.cs..."
BASE_2="$(git rev-parse HEAD)"
echo "// Root domain edit trigger" >> "$ROOT_DIR/src/Core.Domain/Money.cs"
git add "$ROOT_DIR/src/Core.Domain/Money.cs"
git commit -m "test: domain edit" >/dev/null 2>&1
HEAD_2="$(git rev-parse HEAD)"

OUT_2=$("$SELECTOR_SH" "$BASE_2" "$HEAD_2" "$ROOT_DIR" "--dry-run")
echo "$OUT_2" | grep "==> \[RUN\]" || true

if echo "$OUT_2" | grep -q "Order.Api.UnitTests.csproj" && ! echo "$OUT_2" | grep -q "Billing.Api.UnitTests.csproj"; then
    echo "    [PASS] SCENARIO 2: Transitive DAG propagated Core.Domain -> Order.Api.UnitTests!"
else
    echo "    [FAIL] SCENARIO 2: Transitive propagation failed."
    exit 1
fi

# Scenario 3: Committed Documentation-Only Change
echo ""
echo ">>> [SCENARIO 3] Committed Documentation-Only File: docs/test-harness-doc.md..."
BASE_3="$(git rev-parse HEAD)"
mkdir -p "$REPO_ROOT/docs"
echo "# Docs only change" > "$REPO_ROOT/docs/test-harness-doc.md"
git add "$REPO_ROOT/docs/test-harness-doc.md"
git commit -m "test: docs change" >/dev/null 2>&1
HEAD_3="$(git rev-parse HEAD)"

OUT_3=$("$SELECTOR_SH" "$BASE_3" "$HEAD_3" "$ROOT_DIR" "--dry-run")
echo "$OUT_3" | grep -E "\[OK\]|\[WARN\]" || true

if echo "$OUT_3" | grep -q "Documentation-only change detected. Skipping test execution."; then
    echo "    [PASS] SCENARIO 3: Zero tests triggered for docs-only change!"
else
    echo "    [FAIL] SCENARIO 3: Tests were erroneously triggered for documentation."
    exit 1
fi

# Scenario 4: Committed Unmappable Non-Doc File -> Fail-Closed Full Suite
echo ""
echo ">>> [SCENARIO 4] Committed Unmappable Non-Doc: scripts/ci/probe.sh (Fail-Closed)..."
BASE_4="$(git rev-parse HEAD)"
mkdir -p "$REPO_ROOT/scripts/ci"
echo "#!/bin/bash" > "$REPO_ROOT/scripts/ci/probe.sh"
echo "echo probe" >> "$REPO_ROOT/scripts/ci/probe.sh"
git add "$REPO_ROOT/scripts/ci/probe.sh"
git commit -m "test: probe script non-doc" >/dev/null 2>&1
HEAD_4="$(git rev-parse HEAD)"

OUT_4=$("$SELECTOR_SH" "$BASE_4" "$HEAD_4" "$ROOT_DIR" "--dry-run")
echo "$OUT_4" | grep -E "\[WARN\]|==> \[RUN\]" || true

if echo "$OUT_4" | grep -q "Unmappable non-documentation change detected; selecting FULL test suite" && \
   echo "$OUT_4" | grep -q "Billing.Api.UnitTests.csproj" && \
   echo "$OUT_4" | grep -q "Order.Api.UnitTests.csproj"; then
    echo "    [PASS] SCENARIO 4: Fail-closed logic selected full test suite for unmappable non-doc file!"
else
    echo "    [FAIL] SCENARIO 4: Fail-closed full suite selection failed for unmappable non-doc change."
    exit 1
fi

# Scenario 5: Committed Shared Build Config -> Fail-Closed All Suites
echo ""
echo ">>> [SCENARIO 5] Committed Shared Build Config: Directory.Build.props (Fail-Closed)..."
BASE_5="$(git rev-parse HEAD)"
echo "<!-- Shared build config probe -->" >> "$ROOT_DIR/Directory.Build.props"
git add "$ROOT_DIR/Directory.Build.props"
git commit -m "test: Directory.Build.props" >/dev/null 2>&1
HEAD_5="$(git rev-parse HEAD)"

OUT_5=$("$SELECTOR_SH" "$BASE_5" "$HEAD_5" "$ROOT_DIR" "--dry-run")
echo "$OUT_5" | grep -E "\[GLOBAL BUILD CONFIG DETECTED\]|==> \[RUN\]" || true

if echo "$OUT_5" | grep -q "Shared configuration modified; selecting all test suites" && \
   echo "$OUT_5" | grep -q "Billing.Api.UnitTests.csproj" && \
   echo "$OUT_5" | grep -q "Order.Api.UnitTests.csproj"; then
    echo "    [PASS] SCENARIO 5: Fail-closed logic selected all test suites for Directory.Build.props!"
else
    echo "    [FAIL] SCENARIO 5: Expected all test suites to be selected for Directory.Build.props."
    exit 1
fi

# Scenario 6: Multi-Commit Committed Range (2 distinct commits)
echo ""
echo ">>> [SCENARIO 6] Multi-Commit Range (Commit 1: Core.Domain, Commit 2: Billing.Api)..."
BASE_6="$(git rev-parse HEAD)"

# Commit 1
echo "// Range test 1" >> "$ROOT_DIR/src/Core.Domain/Money.cs"
git add "$ROOT_DIR/src/Core.Domain/Money.cs"
git commit -m "test: range commit 1 touching Core.Domain" >/dev/null 2>&1

# Commit 2
echo "// Range test 2" >> "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git add "$ROOT_DIR/src/Billing.Api/InvoiceGenerator.cs"
git commit -m "test: range commit 2 touching Billing.Api" >/dev/null 2>&1

HEAD_6="$(git rev-parse HEAD)"

OUT_6=$("$SELECTOR_SH" "$BASE_6" "$HEAD_6" "$ROOT_DIR" "--dry-run")
echo "$OUT_6" | grep "==> \[RUN\]" || true

if echo "$OUT_6" | grep -q "Order.Api.UnitTests.csproj" && echo "$OUT_6" | grep -q "Billing.Api.UnitTests.csproj"; then
    echo "    [PASS] SCENARIO 6: Multi-commit range correctly selected both Order and Billing test suites!"
else
    echo "    [FAIL] SCENARIO 6: Expected both Order and Billing test suites for multi-commit range."
    exit 1
fi

echo ""
echo "=========================================================="
echo "   ALL 6 TDD SCENARIOS PASSED (TRANSITIVE GRAPH ENGINE VERIFIED)! "
echo "=========================================================="
