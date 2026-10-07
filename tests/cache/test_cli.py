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
from build_cache import cli
from build_cache.adapters import environment


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

    def test_empty_cache_url_is_an_immediate_miss(self):
        args = ["restore", "--kind", "nuget", "--root", str(self.repo)]
        with mock.patch.dict(os.environ, {"CACHE_URL": ""}), redirect_stdout(StringIO()) as out:
            os.environ.pop("BUILD_CACHE_STORE", None)
            self.assertEqual(cli.main(args), 0)
        record = json.loads(out.getvalue())
        self.assertEqual((record["status"], record["detail"]), ("miss", "no store configured"))


if __name__ == "__main__":
    unittest.main()
