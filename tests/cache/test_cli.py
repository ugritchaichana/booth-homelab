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
from support import PATCHED, file_info, tar_bytes
from build_cache import cli
from build_cache.adapters import environment
from build_cache.adapters.fs_store import FilesystemStore
from build_cache.domain.models import Manifest


def git(repo, *args):
    subprocess.run(["git", "-C", str(repo), "-c", "user.name=t", "-c", "user.email=t@t", *args], check=True, capture_output=True)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo, self.store, self.stats = self.tmp / "repo", self.tmp / "store", self.tmp / "stats.jsonl"
        (self.repo / "apps" / "backend" / "obj").mkdir(parents=True)
        (self.repo / "apps" / "fixtures").mkdir(parents=True)
        (self.repo / "apps" / "backend" / "a.cs").write_text("class A {}")
        (self.repo / "apps" / "fixtures" / "f.json").write_text("{}")
        (self.repo / ".gitignore").write_text("obj/\n")
        git(self.repo.parent, "init", "-q", str(self.repo))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", "init")
        (self.repo / "apps" / "backend" / "obj" / "x.dll").write_bytes(b"dll")
        runtime = mock.patch.object(cli, "RUNTIME_VERSION", PATCHED)
        runtime.start()
        self.addCleanup(runtime.stop)
        patch = mock.patch.object(environment, "tool_version", return_value="8.0.425")
        patch.start()
        self.addCleanup(patch.stop)
        self.env = mock.patch.dict(os.environ, {"BUILD_CACHE_WRITER_TOKEN": "t"})
        self.env.start()
        self.addCleanup(self.env.stop)

    def run_cli(self, command, *extra):
        args = [command, "--kind", "dotnet-outputs", "--root", str(self.repo), "--store", f"fs:{self.store}",
                "--stats-file", str(self.stats), "--runner-class", "test", *extra]
        with redirect_stdout(StringIO()) as out:
            code = cli.main(args)
        return code, json.loads(out.getvalue().splitlines()[-1])

    def save_args(self, ref="refs/heads/master"):
        return ["--event", "push", "--ref", ref, "--default-branch", "master"]

    def test_miss_save_hit_cycle_and_report(self):
        self.assertEqual(self.run_cli("restore")[1]["status"], "miss")
        self.assertEqual(self.run_cli("save", *self.save_args())[1]["status"], "saved")
        shutil.rmtree(self.repo / "apps" / "backend" / "obj")
        code, record = self.run_cli("restore")
        self.assertEqual((code, record["status"]), (0, "hit"))
        self.assertEqual((self.repo / "apps" / "backend" / "obj" / "x.dll").read_bytes(), b"dll")
        with redirect_stdout(StringIO()) as out:
            cli.main(["report", "--stats-file", str(self.stats)])
        self.assertIn("dotnet-outputs: 1/2 hit (50.0%)", out.getvalue())

    def test_save_after_a_verified_hit_in_the_same_job_is_skipped_and_after_a_miss_is_written(self):
        self.run_cli("restore")
        self.assertEqual(self.run_cli("save", *self.save_args())[1]["status"], "saved")
        self.assertEqual(self.run_cli("restore")[1]["status"], "hit")
        self.assertEqual(self.run_cli("save", *self.save_args())[1]["status"], "exists")

    def test_an_unpatched_python_refuses_to_extract_and_reports_an_error(self):
        self.run_cli("save", *self.save_args())
        shutil.rmtree(self.repo / "apps" / "backend" / "obj")
        with mock.patch.object(cli, "RUNTIME_VERSION", (3, 12, 10)):
            code, record = self.run_cli("restore")
        self.assertEqual((code, record["status"]), (0, "error"))
        self.assertFalse((self.repo / "apps" / "backend" / "obj").exists())

    def test_an_archive_with_a_member_outside_the_plan_paths_is_rejected_by_the_cli(self):
        self.run_cli("save", *self.save_args())
        shutil.rmtree(self.repo / "apps" / "backend" / "obj")
        store = FilesystemStore(self.store)
        pointer = next((self.store / "pointers").glob("*.json"))
        key = pointer.stem
        evil = gzip.compress(tar_bytes([(file_info("scripts/ci/x.sh", 1), b"x")]))
        sha = hashlib.sha256(evil).hexdigest()
        store.put_blob(sha, evil)
        store.put_pointer(key, Manifest(key, "dotnet-outputs", sha, len(evil), "gzip"))
        code, record = self.run_cli("restore")
        self.assertEqual((code, record["status"]), (0, "rejected"))
        self.assertFalse((self.repo / "scripts").exists())

    def test_save_on_a_non_default_ref_is_skipped(self):
        record = self.run_cli("save", *self.save_args("refs/heads/feature"))[1]
        self.assertEqual(record["status"], "skipped")
        self.assertFalse(self.store.exists())

    def test_changed_source_tree_is_a_miss(self):
        self.run_cli("save", *self.save_args())
        (self.repo / "apps" / "backend" / "a.cs").write_text("class B {}")
        git(self.repo, "commit", "-q", "-am", "change")
        self.assertEqual(self.run_cli("restore")[1]["status"], "miss")

    def test_dirty_inputs_are_a_miss_with_exit_zero(self):
        (self.repo / "apps" / "backend" / "a.cs").write_text("class Dirty {}")
        code, record = self.run_cli("restore")
        self.assertEqual((code, record["status"]), (0, "miss"))
        self.assertIn("cannot derive key", record["detail"])

    def test_missing_store_is_a_miss(self):
        args = ["restore", "--kind", "nuget", "--root", str(self.repo)]
        with mock.patch.dict(os.environ, {}, clear=False), redirect_stdout(StringIO()) as out:
            os.environ.pop("BUILD_CACHE_STORE", None)
            self.assertEqual(cli.main(args), 0)
        self.assertEqual(json.loads(out.getvalue())["status"], "miss")


if __name__ == "__main__":
    unittest.main()
