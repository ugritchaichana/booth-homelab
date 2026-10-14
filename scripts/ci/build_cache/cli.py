from __future__ import annotations

import argparse
import json
import logging
import os
import posixpath
import subprocess
import sys
import time
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath

from .adapters import environment as env
from .adapters.fs_store import FilesystemStore
from .adapters.http_store import HttpStore
from .adapters.tar_archiver import TarArchiver, stamp_extracted
from .application.ports import Outcome, Store
from .application.restore import restore
from .application.save import save
from .domain import keys
from .domain.models import Platform
from .domain.policy import DEFAULT_MAX_BYTES, DEFAULT_MAX_MEMBERS, ExtractionRules, write_decision
from .domain.projects import Project, key_inputs

log = logging.getLogger("build_cache")

RUNTIME_VERSION = tuple(sys.version_info[:3])
FAIL_OPEN = (RuntimeError, ValueError, OSError, subprocess.SubprocessError)
DEFAULT_INPUT_PATHS = ["apps/backend"]
LOCKFILE_SCOPE = {"nuget": ("apps/backend", "packages.lock.json"), "node_modules": ("apps/frontend", "package-lock.json")}
OUTPUT_SEGMENTS = frozenset(env.OUTPUT_DIRS)


@dataclass(frozen=True)
class Plan:
    key: str
    artifact_root: Path
    paths: list[str]
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


def platform_of(args: argparse.Namespace) -> Platform:
    return env.detect_platform(args.runner_class or os.environ.get("BUILD_CACHE_RUNNER_CLASS", "default"))


def dependency_plan(args: argparse.Namespace) -> Plan:
    root = Path(args.root).resolve()
    scope, basename = LOCKFILE_SCOPE[args.kind]
    lockfiles = env.lockfile_digests(root, scope, basename)
    toolchain = env.tool_version("dotnet" if args.kind == "nuget" else "node")
    key = keys.dependency_key(args.kind, platform_of(args), toolchain, lockfiles)
    allowed: tuple[str, ...] = ()
    if args.artifact_root:
        artifact_root, paths = Path(args.artifact_root), ["."]
    elif args.kind == "nuget":
        packages = os.environ.get("NUGET_PACKAGES") or str(Path.home() / ".nuget" / "packages")
        artifact_root, paths = Path(packages), ["."]
    else:
        artifact_root, paths, allowed = root / scope, ["node_modules"], ("node_modules",)
    return Plan(key, artifact_root, paths, extraction_rules(allowed, frozenset()))


def _under(path: str, scopes: list[str]) -> bool:
    return any(path == scope or path.startswith(scope.rstrip("/") + "/") for scope in scopes)


def output_plans(args: argparse.Namespace, discover_outputs: bool) -> list[tuple[str, Plan | Exception]]:
    root = Path(args.root).resolve()
    key_root = os.environ.get("BUILD_CACHE_KEY_ROOT") or root.as_posix()
    if not (PurePosixPath(key_root).is_absolute() or PureWindowsPath(key_root).is_absolute()):
        raise ValueError(f"BUILD_CACHE_KEY_ROOT must be an absolute path, got {key_root!r}")
    platform, sdk = platform_of(args), env.tool_version("dotnet")
    tracked = env.tracked_files(root)
    names = sorted(name for name in tracked if name.lower().endswith(".csproj") and _under(name, args.input_path or DEFAULT_INPUT_PATHS))
    if not names:
        raise ValueError("no project file under the input paths")
    projects: dict[str, Project | Exception] = {}
    for name in names:
        try:
            projects[name] = env.read_project(root, name)
        except ValueError as exc:
            projects[name] = exc
    artifact_root = Path(args.artifact_root) if args.artifact_root else root
    plans: list[tuple[str, Plan | Exception]] = []
    for name in names:
        try:
            inputs = key_inputs(projects, name, tracked)
            if env.git_inputs_dirty(root, inputs):
                raise RuntimeError("working tree differs from HEAD under the project inputs, the object ids would not describe them")
            key = keys.outputs_key(platform, sdk, args.configuration, name, env.git_object_ids(root, inputs), key_root)
            directory = posixpath.dirname(name)
            paths = env.project_output_dirs(artifact_root, directory) if discover_outputs else []
            plans.append((name, Plan(key, artifact_root, paths, extraction_rules((directory,), OUTPUT_SEGMENTS))))
        except FAIL_OPEN as exc:
            plans.append((name, exc))
    return plans


def write_output(name: str, value: str) -> None:
    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as handle:
            handle.write(f"{name}={value}\n")


def emit(outcome: Outcome, args: argparse.Namespace, project: str = "") -> None:
    record = outcome.as_record()
    if project:
        record["project"] = project
    if args.stats_file:
        with open(args.stats_file, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, sort_keys=True) + "\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        subject = f" `{project}`" if project else ""
        line = f"- build-cache {record['op']} `{record['kind']}`{subject} `{record['key']}`: **{record['status']}**, {record['bytes']} bytes, {record['ms']} ms\n"
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(line)
    print(json.dumps(record, sort_keys=True))


def hit_flag(kind: str, hit: bool) -> None:
    write_output(f"cache_hit_{kind.replace('-', '_')}", "true" if hit else "false")


def stamper(root: Path, stamp: int):
    return lambda names: stamp_extracted(root, names, stamp)


def failed(op: str, args: argparse.Namespace, status: str, detail: str) -> Outcome:
    log.warning("%s %s: %s (%s)", op, args.kind, status, detail)
    return Outcome(op, args.kind, "0" * 64, status, 0, 0, detail)


def run_restore(args: argparse.Namespace) -> int:
    try:
        store = make_store(args.store or os.environ.get("BUILD_CACHE_STORE"))
        if store is None:
            emit(failed("restore", args, "miss", "no store configured"), args)
            hit_flag(args.kind, False)
            return 0
        if args.kind in keys.DEPENDENCY_KINDS:
            plan = dependency_plan(args)
            outcome = restore(args.kind, plan.key, plan.artifact_root, store, TarArchiver(version_info=RUNTIME_VERSION), None, plan.rules)
            emit(outcome, args)
            hit_flag(args.kind, outcome.status == "hit")
            return 0
        plans = output_plans(args, discover_outputs=False)
    except FAIL_OPEN as exc:
        emit(failed("restore", args, "miss", f"cannot derive key: {exc}"), args)
        hit_flag(args.kind, False)
        return 0
    stamp = time.time_ns()
    hits = 0
    for name, plan in plans:
        if isinstance(plan, Exception):
            outcome = failed("restore", args, "miss", f"cannot derive key: {plan}")
        else:
            outcome = restore(args.kind, plan.key, plan.artifact_root, store, TarArchiver(version_info=RUNTIME_VERSION), stamper(plan.artifact_root, stamp), plan.rules)
        emit(outcome, args, name)
        hits += outcome.status == "hit"
    hit_flag(args.kind, hits == len(plans))
    write_output(f"restored_{args.kind.replace('-', '_')}", f"{hits}/{len(plans)}")
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
        if args.kind in keys.DEPENDENCY_KINDS:
            plan = dependency_plan(args)
            emit(save(args.kind, plan.key, plan.artifact_root, plan.paths, store, TarArchiver(), decision, restored_hit(args, plan.key)), args)
            return 0
        plans = output_plans(args, discover_outputs=True)
    except FAIL_OPEN as exc:
        emit(failed("save", args, "skipped", f"cannot derive key: {exc}"), args)
        return 0
    for name, plan in plans:
        if isinstance(plan, Exception):
            emit(failed("save", args, "skipped", f"cannot derive key: {plan}"), args, name)
        else:
            emit(save(args.kind, plan.key, plan.artifact_root, plan.paths, store, TarArchiver(), decision, restored_hit(args, plan.key)), args, name)
    return 0


def restored_hit(args: argparse.Namespace, key: str) -> bool:
    if args.restore_status:
        return args.restore_status == "hit"
    if not args.stats_file or not Path(args.stats_file).is_file():
        return False
    status = None
    for line in Path(args.stats_file).read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line) if line.strip() else {}
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and record.get("op") == "restore" and record.get("kind") == args.kind and record.get("key") == keys.short_key(key):
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
