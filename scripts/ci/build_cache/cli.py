from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

from .adapters import environment as env
from .adapters.fs_store import FilesystemStore
from .adapters.http_store import HttpStore
from .adapters.tar_archiver import TarArchiver
from .application.ports import Outcome, Store
from .application.restore import restore, stamp_extracted
from .application.save import save
from .domain import keys
from .domain.policy import DEFAULT_MAX_BYTES, DEFAULT_MAX_MEMBERS, ExtractionRules, supports_safe_extraction, write_decision

log = logging.getLogger("build_cache")

RUNTIME_VERSION = tuple(sys.version_info[:3])
DEFAULT_INPUT_PATHS = ["apps/backend", "apps/fixtures"]
LOCKFILE_SCOPE = {"nuget": ("apps/backend", "packages.lock.json"), "node_modules": ("apps/frontend", "package-lock.json")}


@dataclass(frozen=True)
class Plan:
    key: str
    artifact_root: Path
    paths: list[str]
    is_output: bool
    input_paths: list[str]
    rules: ExtractionRules


def make_store(spec: str | None) -> Store | None:
    if not spec:
        return HttpStore.from_env() if os.environ.get("CACHE_URL") else None
    scheme, _, location = spec.partition(":")
    if scheme == "fs" and location:
        return FilesystemStore(Path(location))
    raise ValueError(f"unsupported store spec: {spec!r}")


def extraction_rules(prefixes: tuple[str, ...], segments: frozenset[str]) -> ExtractionRules:
    return ExtractionRules(
        prefixes,
        segments,
        int(os.environ.get("BUILD_CACHE_MAX_BYTES", DEFAULT_MAX_BYTES)),
        int(os.environ.get("BUILD_CACHE_MAX_MEMBERS", DEFAULT_MAX_MEMBERS)),
    )


def build_plan(args: argparse.Namespace, discover_outputs: bool) -> Plan:
    root = Path(args.root).resolve()
    runner_class = args.runner_class or os.environ.get("BUILD_CACHE_RUNNER_CLASS", "default")
    platform = env.detect_platform(runner_class)
    if args.kind in keys.DEPENDENCY_KINDS:
        scope, basename = LOCKFILE_SCOPE[args.kind]
        lockfiles = env.lockfile_digests(root, scope, basename)
        toolchain = env.tool_version("dotnet" if args.kind == "nuget" else "node")
        key = keys.dependency_key(args.kind, platform, toolchain, lockfiles)
        allowed: tuple[str, ...] = ()
        if args.artifact_root:
            artifact_root, paths = Path(args.artifact_root), ["."]
        elif args.kind == "nuget":
            packages = os.environ.get("NUGET_PACKAGES") or str(Path.home() / ".nuget" / "packages")
            artifact_root, paths = Path(packages), ["."]
        else:
            artifact_root, paths, allowed = root / scope, ["node_modules"], ("node_modules",)
        return Plan(key, artifact_root, paths, False, [], extraction_rules(allowed, frozenset()))

    input_paths = args.input_path or DEFAULT_INPUT_PATHS
    if env.git_inputs_dirty(root, input_paths):
        raise RuntimeError("working tree differs from HEAD under the input paths, the tree ids would not describe the inputs")
    trees = env.git_tree_ids(root, input_paths)
    key = keys.outputs_key(platform, env.tool_version("dotnet"), args.configuration, trees, root.as_posix())
    artifact_root = Path(args.artifact_root) if args.artifact_root else root
    paths = env.discover_output_dirs(root, input_paths) if discover_outputs else []
    return Plan(key, artifact_root, paths, True, input_paths, extraction_rules(tuple(input_paths), frozenset({"bin", "obj"})))


def emit(outcome: Outcome, args: argparse.Namespace) -> None:
    record = outcome.as_record()
    if args.stats_file:
        with open(args.stats_file, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        line = f"- build-cache {record['op']} `{record['kind']}` `{record['key']}`: **{record['status']}**, {record['bytes']} bytes, {record['ms']} ms\n"
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(line)
    output = os.environ.get("GITHUB_OUTPUT")
    if output and outcome.op == "restore":
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"cache_hit_{outcome.kind.replace('-', '_')}={'true' if outcome.status == 'hit' else 'false'}\n")
    print(json.dumps(record, sort_keys=True))


def failed(op: str, args: argparse.Namespace, status: str, detail: str) -> Outcome:
    log.warning("%s %s: %s (%s)", op, args.kind, status, detail)
    return Outcome(op, args.kind, "0" * 64, status, 0, 0, detail)


def run_restore(args: argparse.Namespace) -> int:
    if not supports_safe_extraction(RUNTIME_VERSION):
        version = ".".join(map(str, RUNTIME_VERSION))
        emit(failed("restore", args, "error", f"python {version} is below the patched tarfile releases, extraction refused"), args)
        return 0
    try:
        store = make_store(args.store or os.environ.get("BUILD_CACHE_STORE"))
        if store is None:
            emit(failed("restore", args, "miss", "no store configured"), args)
            return 0
        plan = build_plan(args, discover_outputs=False)
    except (RuntimeError, ValueError, OSError) as exc:
        emit(failed("restore", args, "miss", f"cannot derive key: {exc}"), args)
        return 0
    hook = (lambda names: stamp_extracted(plan.artifact_root, names)) if plan.is_output else None
    emit(restore(args.kind, plan.key, plan.artifact_root, store, TarArchiver(version_info=RUNTIME_VERSION), hook, plan.rules), args)
    return 0


def run_save(args: argparse.Namespace) -> int:
    decision = write_decision(
        bool(os.environ.get(args.credential_env) or os.environ.get("CACHE_WRITER_PASSWORD")),
        args.event or os.environ.get("GITHUB_EVENT_NAME", ""),
        args.ref or os.environ.get("GITHUB_REF", ""),
        args.default_branch,
    )
    try:
        store = make_store(args.store or os.environ.get("BUILD_CACHE_STORE"))
        if store is None:
            emit(failed("save", args, "skipped", "no store configured"), args)
            return 0
        if not decision.allowed:
            emit(failed("save", args, "skipped", decision.reason), args)
            return 0
        plan = build_plan(args, discover_outputs=True)
    except (RuntimeError, ValueError, OSError) as exc:
        emit(failed("save", args, "skipped", f"cannot derive key: {exc}"), args)
        return 0
    hit = restored_hit(args, plan.key)
    emit(save(args.kind, plan.key, plan.artifact_root, plan.paths, store, TarArchiver(), decision, hit), args)
    return 0


def restored_hit(args: argparse.Namespace, key: str) -> bool:
    if args.restore_status:
        return args.restore_status == "hit"
    if not args.stats_file or not Path(args.stats_file).is_file():
        return False
    status = None
    for line in Path(args.stats_file).read_text(encoding="utf-8").splitlines():
        record = json.loads(line) if line.strip() else {}
        if record.get("op") == "restore" and record.get("kind") == args.kind and record.get("key") == key[-64:][:12]:
            status = record["status"]
    return status == "hit"


def run_report(args: argparse.Namespace) -> int:
    counts: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for line in Path(args.stats_file).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        if record.get("op") == "restore":
            counts[record["kind"]][record["status"]] += 1
    total_hits = total = 0
    for kind in sorted(counts):
        tally = counts[kind]
        n = sum(tally.values())
        total, total_hits = total + n, total_hits + tally["hit"]
        print(f"{kind}: {tally['hit']}/{n} hit ({100 * tally['hit'] / n:.1f}%), miss={tally['miss']}, rejected={tally['rejected']}, error={tally['error']}")
    ratio = f"{100 * total_hits / total:.1f}%" if total else "n/a"
    print(f"all: {total_hits}/{total} hit ({ratio})")
    return 0


def _common(sub: argparse.ArgumentParser) -> None:
    sub.add_argument("--kind", required=True, choices=keys.KINDS)
    sub.add_argument("--root", required=True)
    sub.add_argument("--store")
    sub.add_argument("--stats-file")
    sub.add_argument("--runner-class")
    sub.add_argument("--artifact-root")
    sub.add_argument("--configuration", default="Release")
    sub.add_argument("--input-path", action="append")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="build_cache")
    commands = parser.add_subparsers(dest="command", required=True)
    _common(commands.add_parser("restore"))
    saver = commands.add_parser("save")
    _common(saver)
    saver.add_argument("--restore-status", choices=("hit", "miss", "rejected"))
    saver.add_argument("--event")
    saver.add_argument("--ref")
    saver.add_argument("--default-branch", default="master")
    saver.add_argument("--credential-env", default="BUILD_CACHE_WRITER_TOKEN")
    commands.add_parser("report").add_argument("--stats-file", required=True)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, stream=sys.stderr, format="build_cache: %(message)s")
    return {"restore": run_restore, "save": run_save, "report": run_report}[args.command](args)
