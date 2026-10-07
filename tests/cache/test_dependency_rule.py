import ast
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import support
from support import REPO

PACKAGE = "build_cache"
FORBIDDEN = {
    "domain": {"application", "adapters"},
    "application": {"adapters"},
}
INNER_LAYERS = ("domain", "application")
IO_MODULES = {
    "os", "posix", "nt", "subprocess", "socket", "ssl", "http", "urllib",
    "shutil", "tempfile", "tarfile", "zipfile", "glob", "io",
}


def imported_modules(tree: ast.AST, package_parts: list[str]):
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                yield alias.name.split(".")
        elif isinstance(node, ast.ImportFrom):
            base = node.module.split(".") if node.module else []
            if node.level:
                anchor = package_parts[: len(package_parts) - node.level + 1]
                base = anchor + base
            yield base
            for alias in node.names:
                yield base + [alias.name]


def opens_a_file(tree: ast.AST) -> bool:
    return any(
        isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open"
        for node in ast.walk(tree)
    )


def violations(package_root: Path) -> list[str]:
    found = []
    for path in sorted(package_root.rglob("*.py")):
        relative = path.relative_to(package_root)
        name = relative.as_posix()
        layer = relative.parts[0] if len(relative.parts) > 1 else None
        parts = [PACKAGE, *relative.with_suffix("").parts[:-1]]
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for module in imported_modules(tree, parts):
            if module[0] == PACKAGE:
                if len(module) > 1 and module[1] in FORBIDDEN.get(layer, ()):
                    found.append(f"{name} imports {'.'.join(module)}")
            elif module[0] not in sys.stdlib_module_names:
                found.append(f"{name} imports non-stdlib {module[0]}")
            elif layer in INNER_LAYERS and module[0] in IO_MODULES:
                found.append(f"{name} imports I/O module {module[0]}")
        if layer in INNER_LAYERS and opens_a_file(tree):
            found.append(f"{name} calls open")
    return found


class DependencyRuleTests(unittest.TestCase):
    package = REPO / "scripts" / "ci" / PACKAGE

    def test_layers_only_point_inward(self):
        self.assertEqual(violations(self.package), [])

    def test_mutation_domain_importing_an_adapter_is_caught(self):
        self.assert_mutation("domain/keys.py", "from ..adapters import fs_store\n", "adapters")

    def test_mutation_domain_importing_application_is_caught(self):
        self.assert_mutation("domain/policy.py", "import build_cache.application.restore\n", "application")

    def test_mutation_application_importing_an_adapter_is_caught(self):
        self.assert_mutation("application/save.py", "from ..adapters.fs_store import FilesystemStore\n", "adapters")

    def test_mutation_a_non_stdlib_import_in_the_adapters_is_caught(self):
        self.assert_mutation("adapters/environment.py", "import requests\n", "environment.py imports non-stdlib requests")

    def test_mutation_a_non_stdlib_import_in_the_cli_is_caught(self):
        self.assert_mutation("cli.py", "import requests\n", "cli.py imports non-stdlib requests")

    def test_mutation_a_non_stdlib_import_in_the_entry_point_is_caught(self):
        self.assert_mutation("__main__.py", "import requests\n", "__main__.py imports non-stdlib requests")

    def test_mutation_a_non_stdlib_import_in_the_domain_is_caught(self):
        self.assert_mutation("domain/models.py", "import requests\n", "models.py imports non-stdlib requests")

    def test_mutation_the_domain_importing_an_io_module_is_caught(self):
        self.assert_mutation("domain/keys.py", "import os\n", "keys.py imports I/O module os")

    def test_mutation_the_application_importing_an_io_module_is_caught(self):
        self.assert_mutation("application/save.py", "import subprocess\n", "save.py imports I/O module subprocess")

    def test_mutation_an_io_module_imported_from_a_package_is_caught(self):
        self.assert_mutation("application/restore.py", "from urllib.request import urlopen\n", "restore.py imports I/O module urllib")

    def test_mutation_the_application_opening_a_file_is_caught(self):
        self.assert_mutation("application/ports.py", "open('x')\n", "ports.py calls open")

    def test_the_adapters_and_the_cli_may_use_io_modules(self):
        self.assert_clean_after("adapters/fs_store.py", "import socket\n")
        self.assert_clean_after("cli.py", "import socket\n")

    def mutated_copy(self, target: str, line: str) -> Path:
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        copy = tmp / PACKAGE
        shutil.copytree(self.package, copy, ignore=shutil.ignore_patterns("__pycache__"))
        with open(copy / target, "a", encoding="utf-8") as handle:
            handle.write(line)
        return copy

    def assert_mutation(self, target: str, line: str, expect: str):
        found = violations(self.mutated_copy(target, line))
        self.assertTrue(any(expect in item for item in found), found)

    def assert_clean_after(self, target: str, line: str):
        self.assertEqual(violations(self.mutated_copy(target, line)), [])


if __name__ == "__main__":
    unittest.main()
