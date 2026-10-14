import gzip
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from support import PATCHED, file_info, tar_bytes
from build_cache.adapters.tar_archiver import TarArchiver, stamp_extracted
from build_cache.application.ports import Packed
from build_cache.domain.models import ArchiveRejected
from build_cache.domain.policy import ExtractionRules

ZSTD = shutil.which("zstd")
STAMP = 2_000_000_000_000_000_000
OLD = 1_000_000_000_000_000_000


def member_names(packed):
    return sorted(tarfile.open(fileobj=io.BytesIO(gzip.decompress(packed.data))).getnames())


def can_symlink():
    with tempfile.TemporaryDirectory() as d:
        try:
            os.symlink(d, Path(d) / "probe")
        except (OSError, NotImplementedError):
            return False
    return True


class Workspace(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.src, self.dest = self.tmp / "src", self.tmp / "dest"
        (self.src / "obj").mkdir(parents=True)
        (self.src / "obj" / "a.dll").write_bytes(b"binary-a")
        self.archiver = TarArchiver(prefer_zstd=False, version_info=PATCHED)


class PackSelectionTests(Workspace):
    def test_an_absolute_path_is_refused(self):
        with self.assertRaisesRegex(ValueError, "must stay under the root"):
            self.archiver.pack(self.src, ["/abs/x"])

    def test_a_path_listed_twice_through_a_parent_is_archived_once(self):
        packed = self.archiver.pack(self.src, ["obj", "obj/a.dll"])
        self.assertEqual(member_names(packed), ["obj", "obj/a.dll"])

    def test_packing_the_root_itself_archives_its_contents_without_a_dot_member(self):
        self.assertEqual(member_names(self.archiver.pack(self.src, ["."])), ["obj", "obj/a.dll"])

    @unittest.skipUnless(can_symlink(), "symlinks not permitted here")
    def test_a_symlink_to_a_directory_is_archived_as_a_link_and_not_followed(self):
        outside = self.tmp / "outside"
        outside.mkdir()
        (outside / "x.txt").write_text("x", encoding="utf-8")
        os.symlink(outside, self.src / "obj" / "link", target_is_directory=True)
        packed = self.archiver.pack(self.src, ["obj"])
        self.assertEqual(member_names(packed), ["obj", "obj/a.dll", "obj/link"])
        self.assertTrue(tarfile.open(fileobj=io.BytesIO(gzip.decompress(packed.data))).getmember("obj/link").issym())


class RuntimeVersionTests(Workspace):
    def test_the_running_interpreter_version_is_used_unless_one_is_given(self):
        self.assertEqual(TarArchiver(prefer_zstd=False)._version, tuple(sys.version_info[:3]))
        self.assertEqual(TarArchiver(prefer_zstd=False, version_info=(3, 13, 5))._version, (3, 13, 5))


class CompressionFallbackTests(Workspace):
    def archiver_with_a_zstd_binary_named(self):
        with mock.patch("build_cache.adapters.tar_archiver.shutil.which", return_value="zstd"):
            return TarArchiver(version_info=PATCHED)

    def test_a_zstd_run_that_fails_falls_back_to_a_readable_gzip_archive(self):
        failed = subprocess.CompletedProcess([], 1, b"", b"boom")
        with mock.patch("build_cache.adapters.tar_archiver.subprocess.run", return_value=failed):
            packed = self.archiver_with_a_zstd_binary_named().pack(self.src, ["obj"])
        self.assertEqual(packed.compression, "gzip")
        self.archiver.unpack(packed.data, "gzip", self.dest, ExtractionRules())
        self.assertEqual((self.dest / "obj" / "a.dll").read_bytes(), b"binary-a")

    def test_a_zstd_run_that_succeeds_is_recorded_as_zstd(self):
        done = subprocess.CompletedProcess([], 0, b"compressed-bytes", b"")
        with mock.patch("build_cache.adapters.tar_archiver.subprocess.run", return_value=done) as run:
            packed = self.archiver_with_a_zstd_binary_named().pack(self.src, ["obj"])
        self.assertEqual(packed, Packed(b"compressed-bytes", "zstd"))
        self.assertEqual(run.call_args.args[0][0], "zstd")


class DecompressionRefusalTests(Workspace):
    def raw_tar(self):
        return tar_bytes([(file_info("obj/a.dll", 1), b"x")])

    def test_a_truncated_gzip_stream_is_refused(self):
        with self.assertRaisesRegex(ArchiveRejected, "truncated"):
            self.archiver.unpack(gzip.compress(self.raw_tar())[:-10], "gzip", self.dest, ExtractionRules())

    def test_a_manifest_naming_zstd_is_refused_when_no_zstd_binary_is_available(self):
        with self.assertRaisesRegex(ArchiveRejected, "no zstd binary"):
            self.archiver.unpack(b"anything", "zstd", self.dest, ExtractionRules())

    def test_an_unknown_compression_is_refused(self):
        with self.assertRaisesRegex(ArchiveRejected, "unknown compression 'lz4'"):
            self.archiver.unpack(b"anything", "lz4", self.dest, ExtractionRules())


@unittest.skipUnless(ZSTD, "zstd binary not installed")
class ZstdDecompressionTests(Workspace):
    def setUp(self):
        super().setUp()
        self.zstd = TarArchiver(version_info=PATCHED)

    def compress(self, raw):
        return subprocess.run([ZSTD, "-q", "-c"], input=raw, capture_output=True, check=True).stdout

    def test_a_zstd_stream_that_is_not_zstd_is_refused(self):
        with self.assertRaisesRegex(ArchiveRejected, "zstd stream unreadable"):
            self.zstd.unpack(b"this is not a zstd frame", "zstd", self.dest, ExtractionRules())

    def test_a_small_zstd_bomb_is_refused_at_the_limit(self):
        bomb = self.compress(tar_bytes([(file_info("obj/z", 1 << 20), b"\0" * (1 << 20))]))
        with self.assertRaisesRegex(ArchiveRejected, "exceeds the limit"):
            self.zstd.unpack(bomb, "zstd", self.dest, ExtractionRules(max_bytes=10, max_members=0))

    def test_a_zstd_stream_larger_than_the_pipe_is_refused_without_hanging(self):
        large = self.compress(tar_bytes([(file_info("obj/r", 4 << 20), os.urandom(4 << 20))]))
        self.assertGreater(len(large), 1 << 20)
        with self.assertRaisesRegex(ArchiveRejected, "exceeds the limit"):
            self.zstd.unpack(large, "zstd", self.dest, ExtractionRules(max_bytes=10, max_members=0))


class StampTests(Workspace):
    def setUp(self):
        super().setUp()
        self.dest.mkdir()
        self.file = self.dest / "f.txt"
        self.file.write_text("f", encoding="utf-8")
        os.utime(self.file, ns=(OLD, OLD))

    def test_without_a_timestamp_files_get_the_current_time(self):
        stamp_extracted(self.dest, ["f.txt"])
        self.assertLess(abs(self.file.stat().st_mtime_ns - time.time_ns()), 60 * 10**9)

    def test_a_name_that_was_not_extracted_is_skipped_and_the_rest_are_still_stamped(self):
        stamp_extracted(self.dest, ["missing.txt", "f.txt"], STAMP)
        self.assertEqual(self.file.stat().st_mtime_ns, STAMP)

    @unittest.skipUnless(can_symlink() and os.utime in os.supports_follow_symlinks, "needs symlinks and utime without following")
    def test_a_symlink_is_stamped_itself_and_its_target_keeps_its_time(self):
        os.symlink(self.file, self.dest / "link")
        stamp_extracted(self.dest, ["link"], STAMP)
        self.assertEqual((self.dest / "link").lstat().st_mtime_ns, STAMP)
        self.assertEqual(self.file.stat().st_mtime_ns, OLD)

    @unittest.skipUnless(can_symlink(), "symlinks not permitted here")
    def test_a_symlink_is_skipped_on_a_platform_that_cannot_stamp_without_following(self):
        os.symlink(self.file, self.dest / "link")
        with mock.patch.object(os, "supports_follow_symlinks", set()):
            stamp_extracted(self.dest, ["link", "f.txt"], STAMP)
        self.assertEqual(self.file.stat().st_mtime_ns, STAMP)
        self.assertNotEqual((self.dest / "link").lstat().st_mtime_ns, STAMP)


if __name__ == "__main__":
    unittest.main()
