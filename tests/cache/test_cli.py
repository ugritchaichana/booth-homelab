import gzip
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
from unittest import mock

import support  # noqa: F401
from support import PATCHED, file_info, git, tar_bytes
from build_cache import cli
from build_cache.adapters import environment
from build_cache.adapters.fs_store import FilesystemStore
from build_cache.domain.models import Manifest

DOMAIN = "apps/backend/src/Domain/Domain.csproj"
API = "apps/backend/src/Api/Api.csproj"
TESTS = "apps/backend/tests/Api.Tests/Api.Tests.csproj"
PROJECTS = (API, DOMAIN, TESTS)


def csproj(*items):
    return f'<Project Sdk="Microsoft.NET.Sdk"><ItemGroup>{"".join(items)}</ItemGroup></Project>'


class CliTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo, self.store, self.stats = self.tmp / "repo", self.tmp / "store", self.tmp / "stats.jsonl"
        self.output = self.tmp / "github_output"
        files = {
            ".gitignore": "bin/\nobj/\nnode_modules/\n",
            "apps/backend/Directory.Build.props": "<Project />",
            DOMAIN: csproj(),
            "apps/backend/src/Domain/Money.cs": "class Money {}",
            "apps/backend/src/Domain/packages.lock.json": '{"version": 1}',
            API: csproj('<ProjectReference Include="..\\Domain\\Domain.csproj" />'),
            "apps/backend/src/Api/Api.cs": "class Api {}",
            TESTS: csproj('<ProjectReference Include="../../src/Api/Api.csproj" />', '<None Include="..\\..\\..\\fixtures\\cases.json" />'),
            "apps/backend/tests/Api.Tests/ApiTests.cs": "class ApiTests {}",
            "apps/fixtures/cases.json": "{}",
            "apps/frontend/package-lock.json": '{"lockfileVersion": 3}',
            "docs/readme.md": "docs",
        }
        for name, content in files.items():
            self.write(name, content)
        git(self.tmp, "init", "-q", str(self.repo))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "init")
        self.build()
        runtime = mock.patch.object(cli, "RUNTIME_VERSION", PATCHED)
        runtime.start()
        self.addCleanup(runtime.stop)
        patch = mock.patch.object(environment, "tool_version", return_value="8.0.425")
        patch.start()
        self.addCleanup(patch.stop)
        self.env = mock.patch.dict(os.environ, {"BUILD_CACHE_WRITER_TOKEN": "t", "GITHUB_OUTPUT": str(self.output)})
        self.env.start()
        self.addCleanup(self.env.stop)
        for name in ("BUILD_CACHE_STORE", "BUILD_CACHE_KEY_ROOT", "CACHE_URL", "GITHUB_STEP_SUMMARY", "NUGET_PACKAGES"):
            os.environ.pop(name, None)

    def write(self, name, content, root=None):
        path = (root or self.repo) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def build(self, root=None):
        for project in PROJECTS:
            directory = Path(project).parent
            self.write(str(directory / "obj" / "x.dll"), f"obj of {project}", root)
            self.write(str(directory / "bin" / "x.dll"), f"bin of {project}", root)

    def clean(self):
        for project in PROJECTS:
            for name in ("bin", "obj"):
                shutil.rmtree(self.repo / Path(project).parent / name, True)

    def run_cli(self, command, *extra, kind="dotnet-outputs", root=None):
        args = [command, "--kind", kind, "--root", str(root or self.repo), "--store", f"fs:{self.store}",
                "--stats-file", str(self.stats), "--runner-class", "test", *extra]
        with redirect_stdout(StringIO()) as out:
            code = cli.main(args)
        self.assertEqual(code, 0)
        return [json.loads(line) for line in out.getvalue().splitlines()]

    def statuses(self, command, *extra, **kwargs):
        return {record.get("project", ""): record["status"] for record in self.run_cli(command, *extra, **kwargs)}

    def save_args(self, ref="refs/heads/master"):
        return ["--event", "push", "--ref", ref, "--default-branch", "master"]

    def outputs(self):
        lines = self.output.read_text(encoding="utf-8").splitlines() if self.output.exists() else []
        self.output.unlink(missing_ok=True)
        return lines

    def commit(self, name, content):
        self.write(name, content)
        git(self.repo, "commit", "-q", "-am", f"change {name}")


class OutputsCliTests(CliTestCase):
    def test_miss_save_hit_cycle_per_project_and_report(self):
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "miss"))
        self.assertEqual(self.outputs(), ["cache_hit_dotnet_outputs=false", "restored_dotnet_outputs=0/3"])
        self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "saved"))
        self.clean()
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "hit"))
        self.assertEqual(self.outputs(), ["cache_hit_dotnet_outputs=true", "restored_dotnet_outputs=3/3"])
        for project in PROJECTS:
            directory = self.repo / Path(project).parent
            self.assertEqual((directory / "obj" / "x.dll").read_text(), f"obj of {project}")
            self.assertEqual((directory / "bin" / "x.dll").read_text(), f"bin of {project}")
        with redirect_stdout(StringIO()) as out:
            cli.main(["report", "--stats-file", str(self.stats)])
        self.assertIn("dotnet-outputs: 3/6 hit (50.0%)", out.getvalue())

    def test_every_restored_file_gets_one_and_the_same_time(self):
        self.statuses("save", *self.save_args())
        self.clean()
        self.statuses("restore")
        times = {(self.repo / Path(p).parent / d / "x.dll").stat().st_mtime_ns for p in PROJECTS for d in ("bin", "obj")}
        self.assertEqual(len(times), 1)

    def test_a_source_change_misses_only_the_changed_project_and_its_dependents(self):
        self.statuses("save", *self.save_args())
        self.commit("apps/backend/src/Api/Api.cs", "class Api { int x; }")
        self.assertEqual(self.statuses("restore"), {DOMAIN: "hit", API: "miss", TESTS: "miss"})
        self.assertEqual(self.outputs(), ["cache_hit_dotnet_outputs=false", "restored_dotnet_outputs=1/3"])

    def test_a_fixture_change_misses_only_the_project_that_includes_it(self):
        self.statuses("save", *self.save_args())
        self.commit("apps/fixtures/cases.json", '{"case": 1}')
        self.assertEqual(self.statuses("restore"), {DOMAIN: "hit", API: "hit", TESTS: "miss"})

    def test_a_shared_build_file_change_misses_every_project_below_it(self):
        self.statuses("save", *self.save_args())
        self.commit("apps/backend/Directory.Build.props", "<Project><PropertyGroup /></Project>")
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "miss"))

    def test_a_change_outside_every_projects_inputs_still_hits(self):
        self.statuses("save", *self.save_args())
        self.commit("docs/readme.md", "new docs")
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "hit"))

    def test_an_unkeyable_project_misses_with_its_dependents_and_the_rest_still_work(self):
        self.commit(API, csproj('<ProjectReference Include="../Domain/Domain.csproj" />', '<None Include="$(Shared)/x.json" />'))
        by_project = {record["project"]: record for record in self.run_cli("save", *self.save_args())}
        self.assertEqual(by_project[DOMAIN]["status"], "saved")
        for project in (API, TESTS):
            self.assertEqual(by_project[project]["status"], "skipped")
            self.assertIn("cannot derive key", by_project[project]["detail"])
        self.assertEqual(self.statuses("restore"), {DOMAIN: "hit", API: "miss", TESTS: "miss"})

    def test_dirty_inputs_miss_only_the_projects_that_read_them(self):
        self.statuses("save", *self.save_args())
        self.write("apps/backend/tests/Api.Tests/ApiTests.cs", "class Dirty {}")
        by_project = {record["project"]: record for record in self.run_cli("restore")}
        self.assertEqual({p: r["status"] for p, r in by_project.items()}, {DOMAIN: "hit", API: "hit", TESTS: "miss"})
        self.assertIn("cannot derive key", by_project[TESTS]["detail"])

    def test_input_paths_limit_which_projects_are_keyed(self):
        self.assertEqual(self.statuses("restore", "--input-path", "apps/backend/src/"), {API: "miss", DOMAIN: "miss"})

    def test_a_tree_without_projects_is_a_single_miss(self):
        records = self.run_cli("restore", "--input-path", "docs")
        self.assertEqual([(r["status"], "no project file" in r["detail"]) for r in records], [("miss", True)])
        self.assertEqual(self.outputs(), ["cache_hit_dotnet_outputs=false"])

    def test_a_save_job_in_another_checkout_keys_the_entries_by_the_build_root(self):
        save_job = self.tmp / "save-job"
        git(self.tmp, "clone", "-q", str(self.repo), str(save_job))
        self.build(save_job)
        with mock.patch.dict(os.environ, {"BUILD_CACHE_KEY_ROOT": self.repo.resolve().as_posix()}):
            self.assertEqual(self.statuses("save", *self.save_args(), root=save_job), dict.fromkeys(PROJECTS, "saved"))
        self.clean()
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "hit"))
        self.assertEqual(self.statuses("restore", root=save_job), dict.fromkeys(PROJECTS, "miss"))

    def test_a_relative_key_root_is_refused(self):
        with mock.patch.dict(os.environ, {"BUILD_CACHE_KEY_ROOT": "relative/build/root"}):
            records = self.run_cli("save", *self.save_args())
        self.assertEqual([(r["status"], "absolute" in r["detail"]) for r in records], [("skipped", True)])

    def test_save_after_a_verified_hit_in_the_same_job_is_skipped_and_after_a_miss_is_written(self):
        self.statuses("restore")
        self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "saved"))
        self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "hit"))
        self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "exists"))

    def test_an_explicit_restore_status_overrides_the_stats_file(self):
        self.assertEqual(self.statuses("save", *self.save_args(), "--restore-status", "hit"), dict.fromkeys(PROJECTS, "exists"))

    def test_a_project_that_was_not_built_is_saved_as_empty(self):
        for name in ("bin", "obj"):
            shutil.rmtree(self.repo / "apps/backend/tests/Api.Tests" / name)
        self.assertEqual(self.statuses("save", *self.save_args())[TESTS], "empty")

    def test_an_unpatched_python_refuses_to_extract_and_reports_an_error(self):
        self.statuses("save", *self.save_args())
        self.clean()
        with mock.patch.object(cli, "RUNTIME_VERSION", (3, 12, 10)):
            self.assertEqual(self.statuses("restore"), dict.fromkeys(PROJECTS, "error"))
        self.assertFalse((self.repo / "apps/backend/src/Domain/obj").exists())

    def test_an_archive_with_a_member_outside_the_project_is_rejected(self):
        self.statuses("save", *self.save_args())
        domain_key = next(r["key"] for r in self.run_cli("restore") if r["project"] == DOMAIN)
        pointer = next(p for p in (self.store / "pointers").glob("*.json") if p.stem[-64:].startswith(domain_key))
        evil = gzip.compress(tar_bytes([(file_info("apps/backend/src/Api/obj/x.dll", 1), b"x")]))
        sha = hashlib.sha256(evil).hexdigest()
        store = FilesystemStore(self.store)
        store.put_blob(sha, evil)
        store.put_pointer(pointer.stem, Manifest(pointer.stem, "dotnet-outputs", sha, len(evil), "gzip"))
        self.clean()
        self.assertEqual(self.statuses("restore"), {DOMAIN: "rejected", API: "hit", TESTS: "hit"})
        self.assertFalse((self.repo / "apps/backend/src/Domain/obj").exists())

    def test_save_on_a_non_default_ref_is_skipped(self):
        self.assertEqual(self.statuses("save", *self.save_args("refs/heads/feature")), {"": "skipped"})
        self.assertFalse(self.store.exists())

    def test_a_tool_version_timeout_is_a_miss_on_restore_and_a_skip_on_save(self):
        timeout = subprocess.TimeoutExpired(["dotnet", "--version"], 60)
        with mock.patch.object(environment, "tool_version", side_effect=timeout):
            for command, extra, status in (("restore", [], "miss"), ("save", self.save_args(), "skipped")):
                records = self.run_cli(command, *extra)
                self.assertEqual([(r["status"], "cannot derive key" in r["detail"]) for r in records], [(status, True)], command)

    def test_a_corrupt_stats_line_does_not_stop_a_save(self):
        self.stats.write_text("{not json\n", encoding="utf-8")
        self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "saved"))

    def test_a_corrupt_stats_line_next_to_a_valid_hit_still_counts_the_hit(self):
        self.statuses("save", *self.save_args())
        self.statuses("restore")
        with open(self.stats, "a", encoding="utf-8") as handle:
            handle.write("{not json\n[1]\n\n")
        self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "exists"))

    def test_the_step_summary_names_each_project(self):
        summary = self.tmp / "summary.md"
        with mock.patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(summary)}):
            self.statuses("restore")
        lines = summary.read_text(encoding="utf-8").splitlines()
        self.assertEqual(len(lines), 3)
        self.assertIn(f"`dotnet-outputs` `{API}`", lines[0])

    def main_records(self, *args):
        with redirect_stdout(StringIO()) as out:
            self.assertEqual(cli.main(list(args)), 0)
        return {record.get("project", ""): record["status"] for record in map(json.loads, out.getvalue().splitlines())}

    def test_the_runner_class_can_come_from_the_environment(self):
        self.statuses("save", *self.save_args())
        self.clean()
        with mock.patch.dict(os.environ, {"BUILD_CACHE_RUNNER_CLASS": "test"}):
            restored = self.main_records("restore", "--kind", "dotnet-outputs", "--root", str(self.repo), "--store", f"fs:{self.store}")
        self.assertEqual(restored, dict.fromkeys(PROJECTS, "hit"))

    def test_a_save_without_a_stats_file_writes_every_project(self):
        saved = self.main_records("save", "--kind", "dotnet-outputs", "--root", str(self.repo), "--store", f"fs:{self.store}", "--runner-class", "test", *self.save_args())
        self.assertEqual(saved, dict.fromkeys(PROJECTS, "saved"))

    def test_an_input_path_can_name_one_project_file(self):
        self.assertEqual(self.statuses("restore", "--input-path", DOMAIN), {DOMAIN: "miss"})

    def test_a_windows_key_root_counts_as_absolute(self):
        with mock.patch.dict(os.environ, {"BUILD_CACHE_KEY_ROOT": "C:/runner/work/repo"}):
            self.assertEqual(self.statuses("save", *self.save_args()), dict.fromkeys(PROJECTS, "saved"))

    def test_outputs_can_live_under_another_artifact_root(self):
        elsewhere = self.tmp / "elsewhere"
        self.build(elsewhere)
        self.assertEqual(self.statuses("save", *self.save_args(), "--artifact-root", str(elsewhere)), dict.fromkeys(PROJECTS, "saved"))
        shutil.rmtree(elsewhere)
        self.assertEqual(self.statuses("restore", "--artifact-root", str(elsewhere)), dict.fromkeys(PROJECTS, "hit"))
        self.assertEqual((elsewhere / "apps/backend/src/Api/bin/x.dll").read_text(), f"bin of {API}")

    def test_a_hit_recorded_for_another_kind_does_not_skip_the_save(self):
        keys = {record["project"]: record["key"] for record in self.run_cli("restore")}
        with open(self.stats, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"op": "restore", "kind": "nuget", "key": keys[DOMAIN], "status": "hit"}) + "\n")
        self.assertEqual(self.statuses("save", *self.save_args())[DOMAIN], "saved")


class DependencyCliTests(CliTestCase):
    def test_nuget_saves_and_restores_the_package_folder_named_by_the_environment(self):
        packages = self.tmp / "packages"
        self.write("xunit/2.5.3/xunit.nupkg", "package", packages)
        with mock.patch.dict(os.environ, {"NUGET_PACKAGES": str(packages)}):
            self.assertEqual(self.statuses("save", *self.save_args(), kind="nuget"), {"": "saved"})
            shutil.rmtree(packages)
            self.assertEqual(self.statuses("restore", kind="nuget"), {"": "hit"})
        self.assertEqual((packages / "xunit/2.5.3/xunit.nupkg").read_text(), "package")
        self.assertEqual(self.outputs(), ["cache_hit_nuget=true"])

    def test_nuget_defaults_to_the_home_package_folder_and_an_artifact_root_overrides_it(self):
        home = self.tmp / "home"
        self.write(".nuget/packages/a.nupkg", "a", home)
        with mock.patch.object(Path, "home", return_value=home):
            self.assertEqual(self.statuses("save", *self.save_args(), kind="nuget"), {"": "saved"})
        target = self.tmp / "elsewhere"
        self.assertEqual(self.statuses("restore", "--artifact-root", str(target), kind="nuget"), {"": "hit"})
        self.assertEqual((target / "a.nupkg").read_text(), "a")

    def test_node_modules_restore_into_the_frontend_and_a_miss_is_flagged(self):
        self.assertEqual(self.statuses("restore", kind="node_modules"), {"": "miss"})
        self.assertEqual(self.outputs(), ["cache_hit_node_modules=false"])
        self.write("apps/frontend/node_modules/jest/index.js", "module.exports = 1")
        self.assertEqual(self.statuses("save", *self.save_args(), kind="node_modules"), {"": "saved"})
        shutil.rmtree(self.repo / "apps/frontend/node_modules")
        self.assertEqual(self.statuses("restore", kind="node_modules"), {"": "hit"})
        self.assertTrue((self.repo / "apps/frontend/node_modules/jest/index.js").is_file())


class ReportTests(unittest.TestCase):
    def test_blank_lines_and_save_records_are_skipped_and_an_empty_tally_reads_n_a(self):
        with tempfile.TemporaryDirectory() as tmp:
            stats = Path(tmp) / "stats.jsonl"
            stats.write_text('\n{"op": "save", "kind": "nuget", "status": "saved"}\n', encoding="utf-8")
            with redirect_stdout(StringIO()) as out:
                self.assertEqual(cli.main(["report", "--stats-file", str(stats)]), 0)
        self.assertEqual(out.getvalue(), "all: 0/0 hit (n/a)\n")


class StoreConfigurationTests(unittest.TestCase):
    def run_main(self, *args, env=None):
        env = env or {}
        with mock.patch.dict(os.environ, env), redirect_stdout(StringIO()) as out:
            for name in ("BUILD_CACHE_STORE", "CACHE_URL", "GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY", "CACHE_WRITER_PASSWORD"):
                if name not in env:
                    os.environ.pop(name, None)
            code = cli.main(list(args))
        return code, [json.loads(line) for line in out.getvalue().splitlines()]

    def test_no_store_is_a_miss_on_restore_and_a_skip_on_save(self):
        for command, status in (("restore", "miss"), ("save", "skipped")):
            for kind in ("nuget", "dotnet-outputs"):
                code, records = self.run_main(command, "--kind", kind, "--root", ".")
                self.assertEqual((code, [(r["status"], r["detail"]) for r in records]), (0, [(status, "no store configured")]))

    def test_an_empty_cache_url_is_an_immediate_miss(self):
        code, records = self.run_main("restore", "--kind", "nuget", "--root", ".", env={"CACHE_URL": ""})
        self.assertEqual([(r["status"], r["detail"]) for r in records], [("miss", "no store configured")])

    def test_a_cache_url_selects_the_http_store(self):
        with mock.patch.dict(os.environ, {"CACHE_URL": "http://127.0.0.1:9"}):
            self.assertEqual(type(cli.make_store(None)).__name__, "HttpStore")

    def test_an_unknown_store_spec_is_a_miss_with_its_reason(self):
        for spec in ("s3:bucket", "fs:"):
            code, records = self.run_main("restore", "--kind", "nuget", "--root", ".", "--store", spec)
            self.assertEqual([(r["status"], "unsupported store spec" in r["detail"]) for r in records], [("miss", True)], spec)

    def test_the_writer_password_counts_as_a_credential_and_no_credential_skips(self):
        with tempfile.TemporaryDirectory() as tmp:
            args = ("save", "--kind", "nuget", "--root", tmp, "--store", f"fs:{tmp}/s", "--event", "push", "--ref", "refs/heads/master")
            code, records = self.run_main(*args, env={"BUILD_CACHE_WRITER_TOKEN": ""})
            self.assertEqual([r["detail"] for r in records], ["no writer credential"])
            code, records = self.run_main(*args, env={"BUILD_CACHE_WRITER_TOKEN": "", "CACHE_WRITER_PASSWORD": "p"})
            self.assertEqual([(r["status"], "cannot derive key" in r["detail"]) for r in records], [("skipped", True)])


if __name__ == "__main__":
    unittest.main()
