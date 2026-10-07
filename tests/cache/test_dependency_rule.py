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


def imported_modules(path: Path, package_parts: list[str]):
    tree = ast.parse(path.read_text(encoding="utf-8"))
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


def violations(package_root: Path) -> list[str]:
    found = []
    for layer, banned in FORBIDDEN.items():
        for path in sorted((package_root / layer).rglob("*.py")):
            relative = path.relative_to(package_root).with_suffix("")
            parts = [PACKAGE, *relative.parts[:-1]]
            for module in imported_modules(path, parts):
                if module[0] == PACKAGE and len(module) > 1 and module[1] in banned:
                    found.append(f"{path.relative_to(package_root)} imports {'.'.join(module)}")
                if not module[0] == PACKAGE and module[0] not in sys.stdlib_module_names:
                    found.append(f"{path.relative_to(package_root)} imports non-stdlib {module[0]}")
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

    def assert_mutation(self, target: str, line: str, expect: str):
        tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, tmp, True)
        copy = tmp / PACKAGE
        shutil.copytree(self.package, copy, ignore=shutil.ignore_patterns("__pycache__"))
        with open(copy / target, "a", encoding="utf-8") as handle:
            handle.write(line)
        found = violations(copy)
        self.assertTrue(any(expect in item for item in found), found)


if __name__ == "__main__":
    unittest.main()
