#!/usr/bin/env bash
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export PYTHONPATH="$REPO/scripts/ci"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'
export BUILD_CACHE_WRITER_TOKEN=test DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
PROBE=StaleProbeB
SOLUTION=apps/backend/SdetTestingRig.sln
DOMAIN_DLL=apps/backend/src/Core.Domain/bin/Release/net8.0/Core.Domain.dll

WORK="$(mktemp -d "${TMPDIR:-/tmp}/stale-binaries.XXXXXX")"
case "$WORK" in /tmp/*|"${RUNNER_TEMP:-/nonexistent}"/*) ;; *) echo "refusing unsafe work dir $WORK"; exit 2 ;; esac
WS="$WORK/ws"
cleanup() { dotnet build-server shutdown >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

CACHE_ARGS=(--kind dotnet-outputs --store "fs:$WORK/store" --runner-class stale-test)
SAVE_ARGS=(--event push --ref refs/heads/master --default-branch master)

echo "dotnet $(dotnet --version)"

build() { (cd "$1" && dotnet build "$SOLUTION" --configuration Release /p:Deterministic=true -nodeReuse:false "${@:2}"); }
checkout() { rm -rf "$1"; git clone -q "$WORK/origin" "$1" && git -C "$1" checkout -q "$2"; }
has_probe() { grep -qa "$PROBE" "$1/$DOMAIN_DLL"; }
client() { python3 -m build_cache "$1" "${CACHE_ARGS[@]}" --root "$2" "${@:3}" 2>/dev/null | tail -1; }

old_restore() {
    local ROOT_DIR="$1"
    tar -xf "$WORK/latest.tar" -C "$ROOT_DIR"
    cd "$ROOT_DIR"
# MSBuild Timestamp Synchronization:
# Touch all restored dlls and obj inputs to current time so MSBuild sees them as fresh
echo "==> Synchronizing MSBuild Intermediate Timestamps..."
NOW_SEC=$(date +%s)
find "$ROOT_DIR/apps/backend" -type d \( -name "bin" -o -name "obj" \) -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true
find "$ROOT_DIR/apps/backend" -type f \( -name "*.dll" -o -name "*.cache" -o -name "project.assets.json" \) -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true

# Any files modified in git diff against base commit should have timestamps strictly AFTER the output DLLs
# to trigger surgical recompilation for ONLY modified projects
if git rev-parse --verify HEAD~1 >/dev/null 2>&1; then
    BASE_REF="HEAD~1"
else
    BASE_REF="origin/master"
fi

CHANGED_SOURCES=$(git diff --name-only "$BASE_REF" HEAD 2>/dev/null || true)
if [ -n "$CHANGED_SOURCES" ]; then
    FUTURE_SEC=$((NOW_SEC + 5))
    echo "==> Bumping timestamps for $(echo "$CHANGED_SOURCES" | wc -l) modified source files to trigger surgical build..."
    while IFS= read -r f; do
        if [ -f "$f" ]; then
            touch -d "@$FUTURE_SEC" "$f"
            echo "    - Bumped: $f"
        fi
    done <<< "$CHANGED_SOURCES"
fi
}

git clone -q "${CACHE_TEST_SOURCE:-$REPO}" "$WORK/origin" || exit 2
git -C "$WORK/origin" checkout -q -b stale-scenario
COMMIT_A="$(git -C "$WORK/origin" rev-parse HEAD)"
GIT_ID=(-c user.name=probe -c user.email=probe@example.invalid)

printf '\npublic static class %s {}\n' "$PROBE" >> "$WORK/origin/apps/backend/src/Core.Domain/Money.cs"
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -am "probe: add $PROBE to Core.Domain"
COMMIT_B="$(git -C "$WORK/origin" rev-parse HEAD)"
printf '\n// trivial change\n' >> "$WORK/origin/apps/backend/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -am "probe: trivial change in Billing.Api"
COMMIT_C="$(git -C "$WORK/origin" rev-parse HEAD)"
echo "A=${COMMIT_A:0:10} B=${COMMIT_B:0:10} C=${COMMIT_C:0:10}"

checkout "$WS" "$COMMIT_A"
build "$WS" -v:q >"$WORK/build-a.log" 2>&1 || { tail -20 "$WORK/build-a.log"; echo "setup build failed at A"; exit 2; }
(cd "$WS" && tar -cf "$WORK/latest.tar" $(find apps/backend -type d \( -name bin -o -name obj \) -prune))
client save "$WS" "${SAVE_ARGS[@]}" >/dev/null

checkout "$WS" "$COMMIT_C"
sleep 2
(old_restore "$WS") >"$WORK/old-restore.log" 2>&1
build "$WS" -v:d >"$WORK/old-build.log" 2>&1 || { tail -20 "$WORK/old-build.log"; echo "OLD build failed"; exit 2; }
if has_probe "$WS"; then
    OLD=fresh; echo "OLD: not stale"
    grep -a 'is newer than output\|Building target "CoreCompile" completely' "$WORK/old-build.log" | head -10
else OLD=stale; echo "OLD: STALE detected"; fi

checkout "$WS" "$COMMIT_C"
sleep 1
MISS="$(client restore "$WS")"
echo "NEW restore on the changed tree: $MISS"
build "$WS" -v:q >"$WORK/new-build.log" 2>&1 || { tail -20 "$WORK/new-build.log"; echo "NEW build failed"; exit 2; }
if has_probe "$WS" && [[ "$MISS" == *'"status": "miss"'* ]]; then NEW=fresh; echo "NEW: FRESH"; else NEW=stale; echo "NEW: STALE"; fi
client save "$WS" "${SAVE_ARGS[@]}" >/dev/null

checkout "$WS" "$COMMIT_C"
sleep 1
HIT="$(client restore "$WS")"
echo "NEW restore on the saved tree: $HIT"
build "$WS" -v:d >"$WORK/hit-build.log" 2>&1 || { tail -20 "$WORK/hit-build.log"; echo "HIT build failed"; exit 2; }
PROJECTS="$(git -C "$WS" ls-files 'apps/backend/*.csproj' | wc -l)"
SKIPPED="$(grep -c 'Skipping target "CoreCompile"' "$WORK/hit-build.log")"
COMPILED="$(grep -c 'Building target "CoreCompile" completely' "$WORK/hit-build.log")"
echo "CoreCompile skipped in $SKIPPED of $PROJECTS projects, rebuilt in $COMPILED"
if [[ "$HIT" == *'"status": "hit"'* ]] && has_probe "$WS" && [ "$SKIPPED" -eq "$PROJECTS" ] && [ "$COMPILED" -eq 0 ]; then
    HITOK=yes; echo "NEW: HIT up-to-date"
else
    HITOK=no; echo "NEW: HIT not up-to-date"
    grep -a 'is newer than output\|Building target "CoreCompile" completely' "$WORK/hit-build.log" | head -10
fi

[ "$OLD" = stale ] || echo "FAIL: the old algorithm shipped a fresh binary on this SDK, the suspected defect is not reproduced"
[ "$NEW" = fresh ] || echo "FAIL: the new client shipped a stale binary or hit on a changed tree"
[ "$HITOK" = yes ] || echo "FAIL: a hit did not leave every project up to date"
if [ "$OLD" = stale ] && [ "$NEW" = fresh ] && [ "$HITOK" = yes ]; then echo "PASS"; exit 0; fi
exit 1
