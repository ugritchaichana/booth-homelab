import gzip
import shutil
import tempfile
import unittest
from pathlib import Path

from support import PATCHED, MemoryStore, file_info, key_for, publish, tar_bytes
from build_cache.adapters.tar_archiver import TarArchiver
from build_cache.application.restore import restore
from build_cache.domain.policy import ExtractionRules, member_allowed, supports_safe_extraction

OUTPUT_RULES = ExtractionRules(("apps/backend", "apps/fixtures"), frozenset({"bin", "obj"}))
GOOD = "apps/backend/src/Core.Domain/obj/Release/a.dll"


class MemberPolicyTests(unittest.TestCase):
    def test_members_must_sit_under_a_prefix_and_a_required_segment(self):
        self.assertTrue(member_allowed(GOOD, OUTPUT_RULES))
        self.assertTrue(member_allowed("./" + GOOD, OUTPUT_RULES))
        self.assertTrue(member_allowed("apps/backend/src/Core.Domain/bin", OUTPUT_RULES))
        for name in ("scripts/ci/x.sh", "apps/backend/evil.cs", "apps/backendx/obj/a.dll", ".github/workflows/x.yml", "apps"):
            self.assertFalse(member_allowed(name, OUTPUT_RULES), name)

    def test_no_prefix_and_no_segments_allows_everything_under_the_root(self):
        self.assertTrue(member_allowed("anything/at/all", ExtractionRules()))

    def test_minimum_python_versions(self):
        supported = [(3, 11, 13), (3, 11, 14), (3, 12, 11), (3, 12, 12), (3, 13, 4), (3, 13, 5), (3, 14, 0), (3, 15, 0)]
        refused = [(3, 11, 12), (3, 12, 10), (3, 13, 3), (3, 10, 18), (3, 9, 23), (3, 8, 0)]
        for version in supported:
            self.assertTrue(supports_safe_extraction(version), version)
        for version in refused:
            self.assertFalse(supports_safe_extraction(version), version)


class ExtractionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.dest = self.tmp / "dest"
        self.store, self.key = MemoryStore(), key_for("dotnet-outputs", "limits")

    def publish(self, entries, compression="gzip"):
        publish(self.store, self.key, "dotnet-outputs", gzip.compress(tar_bytes(entries)), compression)

    def run_restore(self, rules, version=PATCHED):
        archiver = TarArchiver(prefer_zstd=False, version_info=version)
        return restore("dotnet-outputs", self.key, self.dest, self.store, archiver, None, rules)

    def test_a_valid_archive_still_hits(self):
        self.publish([(file_info(GOOD, 3), b"dll")])
        self.assertEqual(self.run_restore(OUTPUT_RULES).status, "hit")
        self.assertEqual((self.dest / GOOD).read_bytes(), b"dll")

    def test_a_member_outside_the_plan_paths_rejects_everything(self):
        self.publish([(file_info(GOOD, 3), b"dll"), (file_info("scripts/ci/x.sh", 1), b"x")])
        result = self.run_restore(OUTPUT_RULES)
        self.assertEqual(result.status, "rejected")
        self.assertIn("scripts/ci/x.sh", result.detail)
        self.assertFalse(self.dest.exists())

    def test_a_source_file_under_an_input_path_but_outside_bin_and_obj_is_rejected(self):
        self.publish([(file_info("apps/backend/evil.cs", 1), b"x")])
        self.assertEqual(self.run_restore(OUTPUT_RULES).status, "rejected")
        self.assertFalse(self.dest.exists())

    def test_too_many_bytes_is_rejected(self):
        self.publish([(file_info(GOOD, 100), b"x" * 100)])
        result = self.run_restore(ExtractionRules((), frozenset(), max_bytes=10))
        self.assertEqual(result.status, "rejected")
        self.assertFalse(self.dest.exists())

    def test_too_many_members_is_rejected(self):
        self.publish([(file_info(GOOD, 1), b"x"), (file_info(GOOD + "2", 1), b"y")])
        result = self.run_restore(ExtractionRules((), frozenset(), max_members=1))
        self.assertEqual(result.status, "rejected")

    def test_a_decompression_bomb_is_stopped_before_it_is_expanded(self):
        publish(self.store, self.key, "dotnet-outputs", gzip.compress(bytes(8 << 20)), "gzip")
        result = self.run_restore(ExtractionRules((), frozenset(), max_bytes=1000, max_members=10))
        self.assertEqual(result.status, "rejected")
        self.assertIn("exceeds", result.detail)

    def test_a_runtime_below_the_patched_releases_never_extracts(self):
        self.publish([(file_info(GOOD, 3), b"dll")])
        for version in ((3, 12, 10), (3, 13, 3), (3, 11, 12), (3, 10, 18)):
            result = self.run_restore(OUTPUT_RULES, version)
            self.assertEqual(result.status, "error", version)
            self.assertFalse(self.dest.exists())


if __name__ == "__main__":
    unittest.main()
