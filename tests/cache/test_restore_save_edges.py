import gzip
import shutil
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

from support import PATCHED, MemoryStore, file_info, key_for, publish, tar_bytes
from build_cache.adapters.fs_store import FilesystemStore
from build_cache.adapters.tar_archiver import TarArchiver
from build_cache.application.restore import restore
from build_cache.application.save import save
from build_cache.domain.models import BadRequest, ManifestError, StoreUnavailable
from build_cache.domain.policy import WriteDecision

ALLOW = WriteDecision(True, "test")


class BlobFaultStore(MemoryStore):
    def __init__(self, error):
        super().__init__()
        self.error = error

    def get_blob(self, sha256):
        raise self.error


class PointerFaultStore(MemoryStore):
    def get_pointer(self, key):
        raise ManifestError("garbled")


class EdgeCases(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.src, self.dest = self.tmp / "src", self.tmp / "dest"
        (self.src / "obj").mkdir(parents=True)
        (self.src / "obj" / "a.dll").write_bytes(b"binary-a")
        self.archiver = TarArchiver(prefer_zstd=False, version_info=PATCHED)
        self.key = key_for("nuget", "edge")

    def stored(self, store):
        save("nuget", self.key, self.src, ["obj"], store, self.archiver, ALLOW)
        return store


class RestoreEdgeTests(EdgeCases):
    def test_an_unreadable_pointer_is_rejected(self):
        result = restore("nuget", self.key, self.dest, PointerFaultStore(), self.archiver)
        self.assertEqual((result.status, result.detail), ("rejected", "unreadable pointer: garbled"))

    def test_a_corrupt_pointer_file_on_disk_is_rejected(self):
        root = self.tmp / "store"
        (root / "pointers").mkdir(parents=True)
        (root / "pointers" / f"{self.key}.json").write_text("{not json", encoding="utf-8")
        result = restore("nuget", self.key, self.dest, FilesystemStore(root), self.archiver)
        self.assertEqual(result.status, "rejected")

    def test_a_pointer_for_the_right_key_but_another_kind_is_rejected(self):
        store = MemoryStore()
        publish(store, self.key, "dotnet-outputs", gzip.compress(tar_bytes([(file_info("a", 1), b"x")])))
        result = restore("nuget", self.key, self.dest, store, self.archiver)
        self.assertEqual(result.status, "rejected")
        self.assertIn("does not describe", result.detail)

    def test_a_bad_request_while_reading_the_blob_is_an_error(self):
        result = restore("nuget", self.key, self.dest, self.with_pointer(BlobFaultStore(BadRequest("400"))), self.archiver)
        self.assertEqual((result.status, result.detail), ("error", "bad request, client bug: 400"))

    def test_an_unavailable_store_while_reading_the_blob_is_a_miss(self):
        result = restore("nuget", self.key, self.dest, self.with_pointer(BlobFaultStore(StoreUnavailable("down"))), self.archiver)
        self.assertEqual((result.status, result.detail), ("miss", "store unreachable: down"))

    def with_pointer(self, faulty):
        good = self.stored(MemoryStore())
        faulty.pointers = good.pointers
        return faulty

    def test_a_manifest_size_that_disagrees_with_the_blob_is_rejected(self):
        store = self.stored(MemoryStore())
        store.pointers[self.key] = replace(store.pointers[self.key], size=store.pointers[self.key].size + 1)
        result = restore("nuget", self.key, self.dest, store, self.archiver)
        self.assertEqual(result.status, "rejected")
        self.assertFalse(self.dest.exists())

    def test_a_destination_that_is_a_file_is_a_failed_extraction_not_a_crash(self):
        store = self.stored(MemoryStore())
        self.dest.write_text("not a directory", encoding="utf-8")
        result = restore("nuget", self.key, self.dest, store, self.archiver)
        self.assertEqual(result.status, "rejected")
        self.assertIn("extraction failed", result.detail)


class SaveEdgeTests(EdgeCases):
    def test_nothing_to_archive_is_reported_as_empty_and_writes_nothing(self):
        store = MemoryStore()
        result = save("nuget", self.key, self.src, ["absent"], store, self.archiver, ALLOW)
        self.assertEqual((result.status, result.detail), ("empty", "nothing to archive"))
        self.assertEqual(store.calls, [])


if __name__ == "__main__":
    unittest.main()
