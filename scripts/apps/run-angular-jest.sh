#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROOT_DIR="$REPO_ROOT/apps/frontend"
export PYTHONPATH="$REPO_ROOT/scripts/ci${PYTHONPATH:+:$PYTHONPATH}"

echo "=========================================================="
echo "              ANGULAR JEST UNIT TEST RUNNER               "
echo "=========================================================="
echo "Frontend Dir: $ROOT_DIR"
cd "$ROOT_DIR"

START_TIME=$(date +%s%N)

if [ ! -d "node_modules" ]; then
    echo "==> node_modules missing. Restoring from build cache..."
    python3 -m build_cache restore --kind node_modules --root "$REPO_ROOT"
fi

if [ ! -d "node_modules" ]; then
    echo "==> Installing dependencies from the lockfile..."
    npm ci --ignore-scripts --no-audit --no-fund
fi

echo "==> Running Jest Unit Tests for Angular..."
mkdir -p test-results
npx jest --ci --colors --coverage --json --outputFile=test-results/jest.json

END_TIME=$(date +%s%N)
DURATION_MS=$(( (END_TIME - START_TIME) / 1000000 ))

echo "=========================================================="
echo " [SUCCESS] Angular Jest Tests Completed in: ${DURATION_MS} ms"
echo "=========================================================="
