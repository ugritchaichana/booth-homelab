from __future__ import annotations

import hashlib
import platform
import posixpath
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

from ..domain.models import Platform
from ..domain.projects import Project

OUTPUT_DIRS = ("bin", "obj")
MSBUILD_EXPANSIONS = ("$(", "@(", "%(")
WILDCARDS = ("*", "?")


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


def git_object_ids(root: Path, paths: list[str]) -> dict[str, str]:
    ids = _run(["git", "rev-parse", *(f"HEAD:{path}" for path in paths)], cwd=root).splitlines()
    return dict(zip(paths, ids, strict=True))


def tracked_files(root: Path) -> list[str]:
    return [name for name in _run(["git", "ls-files", "-z"], cwd=root).split("\0") if name]


def git_inputs_dirty(root: Path, paths: list[str]) -> bool:
    return bool(_run(["git", "status", "--porcelain", "--", *(path or "." for path in paths)], cwd=root))


def lockfile_digests(root: Path, scope: str, basename: str) -> dict[str, str]:
    listed = _run(["git", "ls-files", "-z", "--", scope], cwd=root).split("\0")
    found = [name for name in listed if name and Path(name).name == basename]
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in found}


def project_output_dirs(root: Path, directory: str) -> list[str]:
    return [posixpath.join(directory, name) for name in OUTPUT_DIRS if (root / directory / name).is_dir()]


def _within(path: str, directory: str) -> bool:
    return not directory or path == directory or path.startswith(directory + "/")


def _repository_path(path: str, directory: str, value: str) -> str:
    resolved = posixpath.normpath(posixpath.join(directory, value.strip().replace("\\", "/")))
    if resolved.startswith("../") or resolved == ".." or posixpath.isabs(resolved):
        raise ValueError(f"{path}: {value!r} points outside the repository")
    return "" if resolved == "." else resolved


def _static_part(path: str, directory: str, value: str) -> str:
    if any(token in value for token in MSBUILD_EXPANSIONS):
        raise ValueError(f"{path}: {value!r} uses an MSBuild expansion, so its inputs cannot be listed")
    cut = min((value.index(w) for w in WILDCARDS if w in value), default=len(value))
    static = value[:cut]
    if cut < len(value):
        static = static.replace("\\", "/").rpartition("/")[0]
    return _repository_path(path, directory, static or ".")


def _path_values(tag: str, element: ET.Element) -> list[str | None]:
    if tag == "Import":
        return [element.get("Project")]
    if tag == "HintPath":
        return [element.text]
    return (element.get("Include") or "").split(";")


def read_project(root: Path, path: str) -> Project:
    try:
        document = ET.parse(root / path)
    except (ET.ParseError, OSError) as exc:
        raise ValueError(f"{path}: unreadable project file: {exc}") from exc
    directory = posixpath.dirname(path)
    references: set[str] = set()
    extra: set[str] = set()
    for element in document.iter():
        tag = element.tag.rpartition("}")[2]
        for value in _path_values(tag, element):
            if not value or not value.strip():
                continue
            if tag == "ProjectReference":
                references.add(_repository_path(path, directory, value))
                continue
            resolved = _static_part(path, directory, value)
            if not _within(resolved, directory) and (tag in ("Import", "HintPath") or (root / resolved).exists()):
                extra.add(resolved)
    return Project(path, tuple(sorted(references)), tuple(sorted(extra)))
