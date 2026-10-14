#!/usr/bin/env bash
# Measures per-project build-output reuse on a generated solution larger than the sample apps.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECTS="${BENCH_PROJECTS:-24}"
RECORDS="${BENCH_RECORDS:-250}"
ROUNDS="${BENCH_ROUNDS:-3}"
export PYTHONPATH="$REPO/scripts/ci" BUILD_CACHE_WRITER_TOKEN=bench DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0='*'

WORK="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bench-large.XXXXXX")"
case "$WORK" in /tmp/*|"${RUNNER_TEMP:-/nonexistent}"/*) ;; *) echo "refusing unsafe work dir $WORK"; exit 2 ;; esac
trap 'dotnet build-server shutdown >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
ORIGIN="$WORK/origin" WS="$WORK/ws"
GIT_ID=(-c user.name=bench -c user.email=bench@example.invalid)
name() { printf 'P%02d' "$1"; }
TOP="gen/$(name $((PROJECTS - 1)))/$(name $((PROJECTS - 1))).csproj"

generate() {
    mkdir -p "$ORIGIN/gen"
    cp "$REPO/apps/backend/Directory.Build.props" "$ORIGIN/gen/Directory.Build.props"
    printf 'bin/\nobj/\n' > "$ORIGIN/.gitignore"
    for i in $(seq 0 $((PROJECTS - 1))); do
        local dir="$ORIGIN/gen/$(name "$i")" ref=""
        mkdir -p "$dir"
        [ "$i" -gt 0 ] && ref="<ItemGroup><ProjectReference Include=\"../$(name $((i - 1)))/$(name $((i - 1))).csproj\" /></ItemGroup>"
        printf '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>%s</Project>\n' "$ref" > "$dir/$(name "$i").csproj"
        {
            echo "namespace $(name "$i");"
            for c in $(seq 0 $((RECORDS - 1))); do
                echo "public record R$c(int A, string B, decimal C) {"
                for m in 0 1 2 3; do
                    echo "  public IEnumerable<decimal> M$m(IEnumerable<R$c> xs) => xs.Where(x => x.A % $((m + 2)) == 0).GroupBy(x => x.B).Select(g => g.Sum(x => x.C * $((m + 1))m)).OrderBy(v => v);"
                done
                echo "}"
            done
        } > "$dir/Gen.cs"
    done
    (cd "$ORIGIN" && dotnet restore "$TOP" >/dev/null) || { echo "restore failed"; exit 2; }
    git -C "$ORIGIN" init -q -b master && git -C "$ORIGIN" add -A && git -C "$ORIGIN" "${GIT_ID[@]}" commit -q -m base
}

checkout() { rm -rf "$WS"; git clone -q "$ORIGIN" "$WS" && (cd "$WS" && dotnet restore "$TOP" >/dev/null); }
client() { python3 -m build_cache "$1" --kind dotnet-outputs --store "fs:$WORK/store" --runner-class bench --input-path gen --root "$WS" "${@:2}" 2>/dev/null; }
build() {
    local start=$(date +%s%N)
    (cd "$WS" && dotnet build "$TOP" -c Release --no-restore -nodeReuse:false "-flp:verbosity=detailed;logfile=$WORK/build.log" "$@" >/dev/null) || { echo "build failed"; exit 2; }
    echo "$(( ($(date +%s%N) - start) / 1000000 )) $(grep -cE 'Building target "CoreCompile" (completely|partially)' "$WORK/build.log") $(grep -c 'Skipping target "CoreCompile"' "$WORK/build.log")"
}
commit_edit() {
    [ -z "$1" ] || printf '\npublic static class Edit%s {}\n' "$RANDOM" >> "$ORIGIN/gen/$1/Gen.cs"
    git -C "$ORIGIN" "${GIT_ID[@]}" commit -q --allow-empty -am "edit ${1:-none}"
}

generate
echo "solution: $PROJECTS projects in a reference chain, $(cat "$ORIGIN"/gen/*/Gen.cs | wc -l) lines; $ROUNDS rounds; dotnet $(dotnet --version)"
declare -A RESULTS
scenario() {
    local label="$1" edit="$2" flags=("${@:3}")
    commit_edit "$edit"
    checkout
    sleep 1
    client restore >/dev/null
    RESULTS["$label"]+="$(build "${flags[@]}");"
    client save --event push --ref refs/heads/master --default-branch master >/dev/null
}
for round in $(seq 1 "$ROUNDS"); do
    rm -rf "$WORK/store"
    checkout
    RESULTS["cold full build"]+="$(build);"
    client save --event push --ref refs/heads/master --default-branch master >/dev/null
    scenario "new commit, same tree" ""
    scenario "one leaf project changed" "$(name $((PROJECTS - 1)))"
    scenario "middle project changed" "$(name $((PROJECTS / 2)))"
    scenario "new commit, commit id in the version" "" /p:IncludeSourceRevisionInInformationalVersion=true
    echo "round $round done"
done

median() { tr ';' '\n' | sed '/^$/d' | sort -n -k1,1 | awk '{a[NR]=$0} END {print a[int((NR + 1) / 2)]}'; }
{
    echo "| Scenario | Median wall time | CoreCompile ran | CoreCompile skipped | Runs (ms) |"
    echo "|---|---|---|---|---|"
    for label in "cold full build" "new commit, same tree" "one leaf project changed" "middle project changed" "new commit, commit id in the version"; do
        read -r ms compiled skipped <<< "$(median <<< "${RESULTS[$label]}")"
        echo "| $label | $ms ms | $compiled | $skipped | $(tr ';' '\n' <<< "${RESULTS[$label]}" | sed '/^$/d' | cut -d' ' -f1 | paste -sd, -) |"
    done
} | tee "$WORK/table.md"
[ -z "${GITHUB_STEP_SUMMARY:-}" ] || cat "$WORK/table.md" >> "$GITHUB_STEP_SUMMARY"
