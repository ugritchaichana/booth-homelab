import hashlib
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import support  # noqa: F401
from support import git
from build_cache.adapters import environment
from build_cache.domain.models import Platform


def write(root: Path, name: str, content: bytes | str = "x") -> None:
    path = root / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content if isinstance(content, bytes) else content.encode())


class TempDirTestCase(unittest.TestCase):
    def make_dir(self) -> Path:
        path = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, path, True)
        return path

    def make_repo(self, files: dict[str, bytes | str]) -> Path:
        repo = self.make_dir() / "repo"
        repo.mkdir()
        git(repo.parent, "init", "-q", str(repo))
        for name, content in files.items():
            write(repo, name, content)
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "init")
        return repo


class DetectPlatformTests(unittest.TestCase):
    def detect(self, os_release, system="Linux", release="6.1.0", machine="X86_64"):
        reader = mock.patch.object(Path, "read_text", **os_release)
        patches = (
            reader,
            mock.patch.object(environment.platform, "system", return_value=system),
            mock.patch.object(environment.platform, "release", return_value=release),
            mock.patch.object(environment.platform, "machine", return_value=machine),
        )
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)
        return environment.detect_platform("lxc-runner")

    def test_table_of_os_release_contents(self):
        cases = [
            ('ID=debian\nVERSION_ID="13"\n', ("debian", "13")),
            ('ID="ubuntu"\nVERSION_ID="24.04"\nNAME="Ubuntu"\n', ("ubuntu", "24.04")),
            ('NAME="Debian"\nID=debian\n', ("debian", "6.1.0")),
            ("VERSION_ID=12\n", ("linux", "12")),
            ("# no key value pairs here\n", ("linux", "6.1.0")),
        ]
        for text, expected in cases:
            with self.subTest(text=text):
                found = self.detect({"return_value": text})
                self.assertEqual((found.os_id, found.os_version), expected)

    def test_a_missing_os_release_falls_back_to_the_running_system(self):
        found = self.detect({"side_effect": FileNotFoundError()}, system="Windows", release="11")
        self.assertEqual(found, Platform("lxc-runner", "windows", "11", "x86_64"))

    def test_the_machine_name_is_lower_cased_and_the_runner_class_is_kept(self):
        found = self.detect({"return_value": "ID=debian\n"}, machine="AArch64")
        self.assertEqual((found.runner_class, found.arch), ("lxc-runner", "aarch64"))


class GitTreeIdsTests(TempDirTestCase):
    FILES = {"apps/backend/a.cs": "class A {}", "apps/fixtures/f.json": "{}", "docs/readme.md": "hi"}

    def test_ids_are_forty_hex_and_one_per_requested_path(self):
        ids = environment.git_tree_ids(self.make_repo(self.FILES), ["apps/backend", "apps/fixtures"])
        self.assertEqual(sorted(ids), ["apps/backend", "apps/fixtures"])
        for value in ids.values():
            self.assertRegex(value, r"^[0-9a-f]{40}$")

    def test_identical_content_in_another_repository_gives_identical_ids(self):
        paths = ["apps/backend", "apps/fixtures"]
        first = environment.git_tree_ids(self.make_repo(self.FILES), paths)
        second = environment.git_tree_ids(self.make_repo(self.FILES), paths)
        self.assertEqual(first, second)

    def test_one_changed_byte_changes_only_its_own_tree(self):
        paths = ["apps/backend", "apps/fixtures"]
        before = environment.git_tree_ids(self.make_repo(self.FILES), paths)
        after = environment.git_tree_ids(self.make_repo({**self.FILES, "apps/backend/a.cs": "class B {}"}), paths)
        self.assertNotEqual(after["apps/backend"], before["apps/backend"])
        self.assertEqual(after["apps/fixtures"], before["apps/fixtures"])

    def test_a_path_missing_from_head_is_an_error(self):
        with self.assertRaises(RuntimeError):
            environment.git_tree_ids(self.make_repo(self.FILES), ["apps/absent"])


class GitInputsDirtyTests(TempDirTestCase):
    def setUp(self):
        self.repo = self.make_repo({"apps/backend/a.cs": "class A {}", "docs/readme.md": "hi", ".gitignore": "obj/\n"})

    def dirty(self):
        return environment.git_inputs_dirty(self.repo, ["apps/backend"])

    def test_a_clean_tree_is_not_dirty(self):
        self.assertFalse(self.dirty())

    def test_table_of_changes_under_the_input_path(self):
        cases = [
            ("modified tracked file", lambda: write(self.repo, "apps/backend/a.cs", "class Dirty {}"), True),
            ("untracked file", lambda: write(self.repo, "apps/backend/new.cs"), True),
            ("staged deletion", lambda: git(self.repo, "rm", "-q", "apps/backend/a.cs"), True),
        ]
        for label, change, expected in cases:
            with self.subTest(label):
                git(self.repo, "reset", "-q", "--hard")
                git(self.repo, "clean", "-qfd")
                change()
                self.assertEqual(self.dirty(), expected)

    def test_changes_outside_the_input_path_and_ignored_files_do_not_count(self):
        write(self.repo, "docs/readme.md", "edited")
        write(self.repo, "apps/backend/obj/x.dll", b"dll")
        self.assertFalse(self.dirty())


class LockfileDigestsTests(TempDirTestCase):
    def test_digests_the_tracked_lockfiles_in_scope_and_nothing_else(self):
        repo = self.make_repo({
            "apps/backend/a/packages.lock.json": b"one",
            "apps/backend/with space/packages.lock.json": b"two",
            "apps/backend/a/other.json": b"skip",
            "apps/frontend/packages.lock.json": b"outside the scope",
        })
        write(repo, "apps/backend/untracked/packages.lock.json", b"not tracked")
        expected = {
            "apps/backend/a/packages.lock.json": hashlib.sha256(b"one").hexdigest(),
            "apps/backend/with space/packages.lock.json": hashlib.sha256(b"two").hexdigest(),
        }
        self.assertEqual(environment.lockfile_digests(repo, "apps/backend", "packages.lock.json"), expected)

    def test_a_scope_without_lockfiles_is_empty(self):
        repo = self.make_repo({"apps/backend/a.cs": "class A {}"})
        self.assertEqual(environment.lockfile_digests(repo, "apps/backend", "packages.lock.json"), {})

    def test_the_digest_follows_the_file_bytes(self):
        repo = self.make_repo({"apps/backend/packages.lock.json": b"one"})
        write(repo, "apps/backend/packages.lock.json", b"two")
        digest = environment.lockfile_digests(repo, "apps/backend", "packages.lock.json")
        self.assertEqual(digest, {"apps/backend/packages.lock.json": hashlib.sha256(b"two").hexdigest()})


class DiscoverOutputDirsTests(TempDirTestCase):
    def test_finds_bin_and_obj_sorted_and_skips_dependency_and_nested_output_trees(self):
        root = self.make_dir()
        for name in (
            "apps/backend/svc/bin/x.dll",
            "apps/backend/svc/obj/y.dll",
            "apps/backend/svc/obj/bin/nested.dll",
            "apps/backend/web/node_modules/pkg/bin/z.js",
            "apps/backend/.git/bin/h",
            "apps/fixtures/tool/bin/f.dll",
            "apps/backend/svc/src/a.cs",
        ):
            write(root, name)
        found = environment.discover_output_dirs(root, ["apps/fixtures", "apps/backend"])
        self.assertEqual(found, ["apps/backend/svc/bin", "apps/backend/svc/obj", "apps/fixtures/tool/bin"])

    def test_an_input_path_that_is_not_a_directory_is_ignored(self):
        root = self.make_dir()
        write(root, "apps/a.cs")
        self.assertEqual(environment.discover_output_dirs(root, ["apps/a.cs", "apps/absent"]), [])


class RunTests(unittest.TestCase):
    def test_a_failing_command_raises_with_its_stderr(self):
        with self.assertRaisesRegex(RuntimeError, re.escape("failed")):
            environment._run(["git", "rev-parse", "--verify", "refs/heads/absent-branch-xyz"])

    def test_a_timeout_propagates_as_a_subprocess_error(self):
        timeout = subprocess.TimeoutExpired(["git"], 60)
        with mock.patch.object(environment.subprocess, "run", side_effect=timeout):
            with self.assertRaises(subprocess.SubprocessError):
                environment._run(["git", "status"])


if __name__ == "__main__":
    unittest.main()
