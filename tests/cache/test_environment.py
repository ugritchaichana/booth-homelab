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


class GitObjectIdsTests(TempDirTestCase):
    FILES = {"apps/backend/a.cs": "class A {}", "apps/fixtures/f.json": "{}", "docs/readme.md": "hi"}

    def test_ids_are_forty_hex_and_one_per_requested_directory_or_file(self):
        ids = environment.git_object_ids(self.make_repo(self.FILES), ["apps/backend", "apps/fixtures/f.json", ""])
        self.assertEqual(list(ids), ["apps/backend", "apps/fixtures/f.json", ""])
        for value in ids.values():
            self.assertRegex(value, r"^[0-9a-f]{40}$")

    def test_identical_content_in_another_repository_gives_identical_ids(self):
        paths = ["apps/backend", "apps/fixtures"]
        first = environment.git_object_ids(self.make_repo(self.FILES), paths)
        second = environment.git_object_ids(self.make_repo(self.FILES), paths)
        self.assertEqual(first, second)

    def test_one_changed_byte_changes_only_its_own_tree_and_the_root(self):
        paths = ["apps/backend", "apps/fixtures", ""]
        before = environment.git_object_ids(self.make_repo(self.FILES), paths)
        after = environment.git_object_ids(self.make_repo({**self.FILES, "apps/backend/a.cs": "class B {}"}), paths)
        self.assertNotEqual(after["apps/backend"], before["apps/backend"])
        self.assertNotEqual(after[""], before[""])
        self.assertEqual(after["apps/fixtures"], before["apps/fixtures"])

    def test_a_path_missing_from_head_is_an_error(self):
        with self.assertRaises(RuntimeError):
            environment.git_object_ids(self.make_repo(self.FILES), ["apps/backend", "apps/absent"])


class TrackedFilesTests(TempDirTestCase):
    def test_lists_tracked_files_with_spaces_and_skips_ignored_and_untracked_ones(self):
        repo = self.make_repo({"a b/c.cs": "x", "d.cs": "y", ".gitignore": "obj/\n"})
        write(repo, "obj/x.dll")
        write(repo, "untracked.cs")
        self.assertEqual(sorted(environment.tracked_files(repo)), [".gitignore", "a b/c.cs", "d.cs"])


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

    def test_the_repository_root_is_named_by_an_empty_path(self):
        self.assertFalse(environment.git_inputs_dirty(self.repo, [""]))
        write(self.repo, "docs/readme.md", "changed")
        self.assertTrue(environment.git_inputs_dirty(self.repo, [""]))

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


class ProjectOutputDirsTests(TempDirTestCase):
    def test_finds_only_the_projects_own_bin_and_obj(self):
        root = self.make_dir()
        for name in ("apps/svc/bin/x.dll", "apps/svc/obj/y.dll", "apps/svc/sub/bin/nested.dll", "apps/other/obj/z.dll", "apps/svc/a.cs"):
            write(root, name)
        self.assertEqual(environment.project_output_dirs(root, "apps/svc"), ["apps/svc/bin", "apps/svc/obj"])

    def test_a_project_that_was_not_built_has_none(self):
        root = self.make_dir()
        write(root, "apps/svc/a.cs")
        write(root, "apps/svc/obj", "a file named obj is not an output directory")
        self.assertEqual(environment.project_output_dirs(root, "apps/svc"), [])


def project_file(*items: str, namespace: str = "") -> str:
    xmlns = f' xmlns="{namespace}"' if namespace else ""
    return f'<Project Sdk="Microsoft.NET.Sdk"{xmlns}><ItemGroup>{"".join(items)}</ItemGroup></Project>'


class ReadProjectTests(TempDirTestCase):
    PATH = "apps/backend/tests/Api.Tests/Api.Tests.csproj"

    def read(self, *items: str, files: tuple[str, ...] = (), namespace: str = ""):
        root = self.make_dir()
        write(root, self.PATH, project_file(*items, namespace=namespace))
        for name in files:
            write(root, name)
        return environment.read_project(root, self.PATH)

    def test_project_references_resolve_to_repository_paths_whatever_the_separator(self):
        project = self.read('<ProjectReference Include="..\\..\\src\\Api\\Api.csproj" />', '<ProjectReference Include="../../src/App/App.csproj" />')
        self.assertEqual(project.references, ("apps/backend/src/Api/Api.csproj", "apps/backend/src/App/App.csproj"))
        self.assertEqual(project.extra_inputs, ())

    def test_a_file_outside_the_project_directory_is_an_extra_input_only_when_it_exists(self):
        project = self.read(
            '<None Include="..\\..\\..\\fixtures\\cases.json" />',
            '<None Include="../../../fixtures/absent.json" />',
            files=("apps/fixtures/cases.json",),
        )
        self.assertEqual(project.extra_inputs, ("apps/fixtures/cases.json",))

    def test_items_inside_the_project_directory_and_names_that_are_not_paths_add_nothing(self):
        project = self.read(
            '<PackageReference Include="xunit" Version="2.5.3" />',
            '<Using Include="Xunit" />',
            '<None Update="xunit.runner.json" />',
            '<Compile Include="Generated/**/*.cs" />',
            '<None Include="local.json" />',
            files=("apps/backend/tests/Api.Tests/local.json",),
        )
        self.assertEqual((project.references, project.extra_inputs), ((), ()))

    def test_a_wildcard_outside_the_project_directory_keys_its_static_directory(self):
        project = self.read('<Compile Include="..\\..\\shared\\**\\*.cs" />', files=("apps/backend/shared/a/b.cs",))
        self.assertEqual(project.extra_inputs, ("apps/backend/shared",))

    def test_a_wildcard_over_the_whole_project_directory_adds_nothing(self):
        self.assertEqual(self.read('<Compile Include="**/*.cs" />').extra_inputs, ())

    def test_an_include_of_the_repository_root_keys_the_whole_tree(self):
        self.assertEqual(self.read('<None Include="../../../../" />').extra_inputs, ("",))

    def test_a_project_at_the_repository_root_owns_every_path(self):
        root = self.make_dir()
        write(root, "Root.csproj", project_file('<None Include="apps/fixtures/cases.json" />'))
        write(root, "apps/fixtures/cases.json")
        self.assertEqual(environment.read_project(root, "Root.csproj").extra_inputs, ())

    def test_a_semicolon_list_is_split_and_blank_entries_are_ignored(self):
        project = self.read('<None Include="../../../fixtures/a.json; ;../../../fixtures/b.json" />', files=("apps/fixtures/a.json", "apps/fixtures/b.json"))
        self.assertEqual(project.extra_inputs, ("apps/fixtures/a.json", "apps/fixtures/b.json"))

    def test_an_import_and_a_hint_path_outside_the_directory_count_even_before_they_exist(self):
        project = self.read(
            '</ItemGroup><Import Project="../../build/common.props" /><Import Project="Local.props" /><ItemGroup>',
            '<Reference Include="Vendor"><HintPath>../../lib/Vendor.dll</HintPath></Reference>',
            '<Reference Include="Empty"><HintPath></HintPath></Reference>',
        )
        self.assertEqual(project.extra_inputs, ("apps/backend/build/common.props", "apps/backend/lib/Vendor.dll"))

    def test_a_namespaced_project_file_is_read_like_an_sdk_one(self):
        project = self.read('<ProjectReference Include="../../src/Api/Api.csproj" />', namespace="http://schemas.microsoft.com/developer/msbuild/2003")
        self.assertEqual(project.references, ("apps/backend/src/Api/Api.csproj",))

    def test_inputs_that_cannot_be_listed_make_the_project_unkeyable(self):
        cases = (
            ("an MSBuild property", '<None Include="$(SharedDir)/cases.json" />', "MSBuild expansion"),
            ("an item transform", '<None Include="@(Other)" />', "MSBuild expansion"),
            ("a path above the repository", '<None Include="../../../../../outside.json" />', "outside the repository"),
            ("the directory above the repository", '<None Include="../../../../.." />', "outside the repository"),
            ("an absolute path", '<ProjectReference Include="/etc/Api.csproj" />', "outside the repository"),
        )
        for name, item, message in cases:
            with self.subTest(name), self.assertRaisesRegex(ValueError, message):
                self.read(item)

    def test_an_unreadable_or_missing_project_file_is_unkeyable(self):
        root = self.make_dir()
        write(root, self.PATH, "<Project><ItemGroup>")
        with self.assertRaisesRegex(ValueError, "unreadable project file"):
            environment.read_project(root, self.PATH)
        with self.assertRaisesRegex(ValueError, "unreadable project file"):
            environment.read_project(root, "apps/absent/Absent.csproj")


class ToolVersionTests(unittest.TestCase):
    def test_reports_what_the_tool_prints_for_its_version(self):
        self.assertRegex(environment.tool_version("git"), r"^git version [0-9]")


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
