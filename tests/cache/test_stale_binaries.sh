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
GIT_ID=(-c user.name=probe -c user.email=probe@example.invalid)

echo "dotnet $(dotnet --version)"

build() { (cd "$WS" && dotnet build "$SOLUTION" --configuration Release /p:Deterministic=true -nodeReuse:false "$@"); }
# GitHub-shaped origin, as in CI, so Source Link runs.
checkout() { rm -rf "$WS"; git clone -q "$WORK/origin" "$WS" && git -C "$WS" remote set-url origin https://github.com/example/sdet-testing-rig.git && git -C "$WS" checkout -q "$1"; }
has_probe() { grep -qa "$PROBE" "$WS/$DOMAIN_DLL"; }
client() { python3 -m build_cache "$1" "${CACHE_ARGS[@]}" --root "$WS" "${@:2}" 2>/dev/null; }
statuses() { grep -c "\"status\": \"$1\"" <<< "$2"; }
compiled() { grep -c 'Building target "CoreCompile" completely' "$1"; }
skipped() { grep -c 'Skipping target "CoreCompile"' "$1"; }

old_restore() {
    local ROOT_DIR="$1"
    tar -xf "$LATEST" -C "$ROOT_DIR"
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
    if [ "${EXTRA_TOUCH:-none}" = pdb ]; then
        find "$ROOT_DIR/apps/backend" -type f -name "*.pdb" -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true
    elif [ "${EXTRA_TOUCH:-none}" = all ]; then
        find "$ROOT_DIR/apps/backend" -type f \( -path "*/bin/*" -o -path "*/obj/*" \) -exec touch -t "$(date -d @$NOW_SEC +%Y%m%d%H%M.%S)" {} + 2>/dev/null || true
    fi
}

snapshot_a() {
    checkout "$COMMIT_A"
    build -v:q "${@:2}" >"$WORK/build-a-$1.log" 2>&1 || { tail -20 "$WORK/build-a-$1.log"; echo "setup build failed at A"; exit 2; }
    (cd "$WS" && tar -cf "$WORK/latest-$1.tar" $(find apps/backend -type d \( -name bin -o -name obj \) -prune))
}

old_variant() {
    checkout "$COMMIT_C"
    sleep 2
    (LATEST="$WORK/latest-$2.tar" EXTRA_TOUCH="$1" old_restore "$WS") >"$WORK/old-restore.log" 2>&1
    build -v:d "${@:3}" >"$WORK/old-build-$1.log" 2>&1 || { tail -20 "$WORK/old-build-$1.log"; echo "OLD build failed"; exit 2; }
    has_probe && return 1 || return 0
}

mkdir "$WORK/origin"
git -C "${CACHE_TEST_SOURCE:-$REPO}" archive HEAD | tar -x -C "$WORK/origin" || exit 2
git -C "$WORK/origin" init -q -b stale-scenario
git -C "$WORK/origin" add -A
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -m "scenario: base tree"
COMMIT_A="$(git -C "$WORK/origin" rev-parse HEAD)"
printf '\npublic static class %s {}\n' "$PROBE" >> "$WORK/origin/apps/backend/src/Core.Domain/Money.cs"
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -am "probe: add $PROBE to Core.Domain"
COMMIT_B="$(git -C "$WORK/origin" rev-parse HEAD)"
printf '\n// trivial change\n' >> "$WORK/origin/apps/backend/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -am "probe: trivial change in Billing.Api"
COMMIT_C="$(git -C "$WORK/origin" rev-parse HEAD)"
echo "A=${COMMIT_A:0:10} B=${COMMIT_B:0:10} C=${COMMIT_C:0:10}"

NOREV=/p:IncludeSourceRevisionInInformationalVersion=false
snapshot_a default
snapshot_a norev "$NOREV"

if old_variant none default; then
    echo "OLD-as-shipped: STALE"
elif grep -aq 'newer than output file .*\.pdb' "$WORK/old-build-none.log"; then
    echo "OLD-as-shipped: not stale (pdb mtime forces CoreCompile)"
else
    echo "OLD-as-shipped: not stale (see log)"
fi

if old_variant pdb default; then
    echo "OLD+pdb: STALE"
elif grep -aq 'AssemblyInfo.cs" is newer than output file .*\.dll' "$WORK/old-build-pdb.log"; then
    echo "OLD+pdb: not stale (a regenerated AssemblyInfo.cs forces CoreCompile)"
else
    echo "OLD+pdb: not stale (see log)"
fi

if old_variant all norev "$NOREV"; then
    OLDALL=stale; echo "OLD+all-outputs-touched+no-revision-in-version: STALE detected"
else
    OLDALL=fresh; echo "OLD+all-outputs-touched+no-revision-in-version: not stale"
    grep -a 'is newer than output\|Building target "CoreCompile" completely' "$WORK/old-build-all.log" | head -10
fi

checkout "$COMMIT_C"
sleep 1
MISS="$(client restore)"
echo "NEW restore on the changed tree: $(statuses hit "$MISS") hits"
build -v:q >"$WORK/new-build.log" 2>&1 || { tail -20 "$WORK/new-build.log"; echo "NEW build failed"; exit 2; }
if has_probe && [ "$(statuses hit "$MISS")" -eq 0 ]; then NEW=fresh; echo "NEW: FRESH"; else NEW=stale; echo "NEW: STALE"; fi
SAVED="$(client save "${SAVE_ARGS[@]}")"
echo "NEW save: $(statuses saved "$SAVED") saved"
grep -v '"status": "saved"' <<< "$SAVED" | head -3

checkout "$COMMIT_C"
sleep 1
HIT="$(client restore)"
echo "NEW restore on the saved tree: $(statuses hit "$HIT") hits"
build -v:d >"$WORK/hit-build.log" 2>&1 || { tail -20 "$WORK/hit-build.log"; echo "HIT build failed"; exit 2; }
PROJECTS="$(git -C "$WS" ls-files 'apps/backend/*.csproj' | wc -l)"
SKIPPED="$(skipped "$WORK/hit-build.log")"
COMPILED="$(compiled "$WORK/hit-build.log")"
if [ "$(statuses hit "$HIT")" -eq "$PROJECTS" ] && has_probe && [ "$SKIPPED" -eq "$PROJECTS" ] && [ "$COMPILED" -eq 0 ]; then
    HITOK=yes; echo "NEW: HIT up-to-date (CoreCompile skipped $SKIPPED/$PROJECTS)"
else
    HITOK=no; echo "NEW: HIT not up-to-date (CoreCompile skipped $SKIPPED/$PROJECTS, rebuilt $COMPILED)"
    grep -a 'is newer than output\|Building target "CoreCompile" completely' "$WORK/hit-build.log" | head -10
fi

git -C "$WORK/origin" "${GIT_ID[@]}" commit -q --allow-empty -m "probe: a new commit with the same tree"
COMMIT_D="$(git -C "$WORK/origin" rev-parse HEAD)"
checkout "$COMMIT_D"
sleep 1
SAME="$(client restore)"
build -v:d >"$WORK/same-tree-build.log" 2>&1 || { tail -20 "$WORK/same-tree-build.log"; echo "same-tree build failed"; exit 2; }
SKIPPED="$(skipped "$WORK/same-tree-build.log")"; COMPILED="$(compiled "$WORK/same-tree-build.log")"
if [ "$(statuses hit "$SAME")" -eq "$PROJECTS" ] && [ "$SKIPPED" -eq "$PROJECTS" ] && [ "$COMPILED" -eq 0 ]; then
    SAMEOK=yes; echo "NEW: a new commit with the same tree reuses every project (CoreCompile skipped $SKIPPED/$PROJECTS)"
else
    SAMEOK=no; echo "NEW: a new commit with the same tree rebuilt $COMPILED of $PROJECTS projects ($(statuses hit "$SAME") hits)"
    grep -a 'is newer than output' "$WORK/same-tree-build.log" | head -5
fi

SPLIT_PROBE=SplitProbeE
printf '\npublic static class %s {}\n' "$SPLIT_PROBE" >> "$WORK/origin/apps/backend/src/Billing.Api/InvoiceGenerator.cs"
git -C "$WORK/origin" "${GIT_ID[@]}" commit -q -am "probe: change Billing.Api only"
COMMIT_E="$(git -C "$WORK/origin" rev-parse HEAD)"
checkout "$COMMIT_E"
AFFECTED="$(cd "$WS" && bash scripts/apps/dotnet-affected-test.sh "$COMMIT_D" "$COMMIT_E" "$WS/apps/backend" true | sed -n 's/.*Total Transitive Projects Affected: *//p')"
sleep 1
SPLIT="$(client restore)"
build -v:d >"$WORK/split-build.log" 2>&1 || { tail -20 "$WORK/split-build.log"; echo "split build failed"; exit 2; }
SKIPPED="$(skipped "$WORK/split-build.log")"; COMPILED="$(compiled "$WORK/split-build.log")"
REUSED=$((PROJECTS - AFFECTED))
if [ "$(statuses hit "$SPLIT")" -eq "$REUSED" ] && [ "$SKIPPED" -eq "$REUSED" ] && [ "$COMPILED" -eq "$AFFECTED" ] && grep -qa "$SPLIT_PROBE" "$WS/apps/backend/src/Billing.Api/bin/Release/net8.0/Billing.Api.dll"; then
    SPLITOK=yes; echo "NEW: a one-project change compiled $COMPILED affected projects and reused $SKIPPED of $PROJECTS"
else
    SPLITOK=no; echo "NEW: a one-project change compiled $COMPILED and skipped $SKIPPED of $PROJECTS (expected $AFFECTED and $REUSED, $(statuses hit "$SPLIT") hits)"
fi

[ "$OLDALL" = stale ] || echo "FAIL: the detector cannot fail: the old algorithm with every output touched shipped a fresh binary"
[ "$NEW" = fresh ] || echo "FAIL: the new client shipped a stale binary or hit on a changed tree"
[ "$HITOK" = yes ] || echo "FAIL: a hit did not leave every project up to date"
[ "$SAMEOK" = yes ] || echo "FAIL: a new commit with an unchanged tree recompiled"
[ "$SPLITOK" = yes ] || echo "FAIL: a one-project change did not reuse the other projects, or shipped a stale binary"
if [ "$OLDALL" = stale ] && [ "$NEW" = fresh ] && [ "$HITOK" = yes ] && [ "$SAMEOK" = yes ] && [ "$SPLITOK" = yes ]; then echo "PASS"; exit 0; fi
exit 1
