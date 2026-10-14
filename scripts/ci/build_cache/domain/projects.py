from __future__ import annotations

import posixpath
from dataclasses import dataclass
from typing import Iterable, Mapping

SHARED_BUILD_FILES = frozenset(
    {
        "directory.build.props",
        "directory.build.targets",
        "directory.build.rsp",
        "directory.packages.props",
        "global.json",
        "nuget.config",
        ".editorconfig",
        ".globalconfig",
    }
)


@dataclass(frozen=True)
class Project:
    path: str
    references: tuple[str, ...] = ()
    extra_inputs: tuple[str, ...] = ()

    @property
    def directory(self) -> str:
        return posixpath.dirname(self.path)


def closure(projects: Mapping[str, Project | Exception], path: str) -> list[Project]:
    seen: dict[str, Project] = {}
    pending = [path]
    while pending:
        current = pending.pop()
        if current in seen:
            continue
        found = projects.get(current)
        if found is None:
            raise ValueError(f"{current} is referenced but is not a project under the input paths")
        if isinstance(found, Exception):
            raise ValueError(f"{current} cannot be keyed: {found}")
        seen[current] = found
        pending.extend(found.references)
    return [seen[name] for name in sorted(seen)]


def ancestors(directory: str) -> set[str]:
    found = {""}
    current = directory
    while current:
        found.add(current)
        current = posixpath.dirname(current)
    return found


def shared_files(tracked: Iterable[str], directory: str) -> list[str]:
    wanted = ancestors(directory)
    return sorted(f for f in tracked if posixpath.dirname(f) in wanted and posixpath.basename(f).lower() in SHARED_BUILD_FILES)


def key_inputs(projects: Mapping[str, Project | Exception], path: str, tracked: Iterable[str]) -> list[str]:
    tracked = list(tracked)
    inputs: set[str] = set()
    for project in closure(projects, path):
        inputs.add(project.directory)
        inputs.update(project.extra_inputs)
        inputs.update(shared_files(tracked, project.directory))
    return sorted(inputs)
