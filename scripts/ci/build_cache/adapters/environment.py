from __future__ import annotations

import hashlib
import os
import platform
import subprocess
from pathlib import Path

from ..domain.models import Platform

SKIPPED_DIRS = {"bin", "obj", "node_modules", ".git"}


def _run(command: list[str], cwd: Path | None = None) -> str:
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True, timeout=60)
    if done.returncode != 0:
        raise RuntimeError(f"{' '.join(command)} failed: {done.stderr.strip()}")
    return done.stdout.strip()


def tool_version(tool: str) -> str:
    return _run([tool, "--version"])


def detect_platform(runner_class: str) -> Platform:
    os_id, os_version = platform.system().lower(), platform.release()
    try:
        fields = dict(
            line.split("=", 1)
            for line in Path("/etc/os-release").read_text().splitlines()
            if "=" in line
        )
        os_id = fields.get("ID", os_id).strip('"')
        os_version = fields.get("VERSION_ID", os_version).strip('"')
    except OSError:
        pass
    return Platform(runner_class, os_id, os_version, platform.machine().lower())


def git_tree_ids(root: Path, paths: list[str]) -> dict[str, str]:
    return {path: _run(["git", "rev-parse", f"HEAD:{path}"], cwd=root) for path in paths}


def git_inputs_dirty(root: Path, paths: list[str]) -> bool:
    return bool(_run(["git", "status", "--porcelain", "--", *paths], cwd=root))


def lockfile_digests(root: Path, scope: str, basename: str) -> dict[str, str]:
    listed = _run(["git", "ls-files", "-z", "--", scope], cwd=root).split("\0")
    found = [name for name in listed if name and Path(name).name == basename]
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in found}


def discover_output_dirs(root: Path, input_paths: list[str]) -> list[str]:
    found: list[str] = []
    for input_path in input_paths:
        base = root / input_path
        if not base.is_dir():
            continue
        for current, dirs, _ in os.walk(base):
            for name in list(dirs):
                if name in ("bin", "obj"):
                    found.append((Path(current) / name).relative_to(root).as_posix())
            dirs[:] = [d for d in dirs if d not in SKIPPED_DIRS]
    return sorted(found)
