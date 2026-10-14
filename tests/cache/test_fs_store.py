import hashlib
import shutil
import tempfile
import unittest
from pathlib import Path

from support import key_for
from build_cache.adapters.fs_store import FilesystemStore
from build_cache.domain.models import Manifest, ManifestError, StoreUnavailable

DATA = b"blob-bytes"
DIGEST = hashlib.sha256(DATA).hexdigest()


class FilesystemStoreEdgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.root = self.tmp / "store"
        self.store = FilesystemStore(self.root)
        self.key = key_for("nuget", "fs")

    def leftovers(self):
        return [p for p in self.root.rglob(".tmp-*")]

    def test_a_pointer_round_trips(self):
        manifest = Manifest(key=self.key, kind="nuget", sha256=DIGEST, size=len(DATA), compression="gzip")
        self.store.put_pointer(self.key, manifest)
        self.assertEqual(self.store.get_pointer(self.key), manifest)

    def test_putting_an_existing_blob_again_leaves_the_first_copy_untouched(self):
        self.store.put_blob(DIGEST, DATA)
        blob = self.root / "blobs" / DIGEST[:2] / DIGEST
        first = blob.stat().st_mtime_ns
        self.store.put_blob(DIGEST, b"different bytes the store must not accept")
        self.assertEqual((blob.read_bytes(), blob.stat().st_mtime_ns), (DATA, first))

    def test_a_malformed_blob_digest_is_refused(self):
        for digest in ("zz", "../" + "a" * 61, "A" * 64):
            with self.assertRaises(ValueError, msg=digest):
                self.store.get_blob(digest)
            with self.assertRaises(ValueError, msg=digest):
                self.store.put_blob(digest, DATA)

    def test_a_pointer_file_that_is_not_a_manifest_is_a_manifest_error(self):
        (self.root / "pointers").mkdir(parents=True)
        (self.root / "pointers" / f"{self.key}.json").write_text("{not json", encoding="utf-8")
        with self.assertRaises(ManifestError):
            self.store.get_pointer(self.key)

    def test_a_pointer_that_cannot_be_read_is_the_store_being_unavailable(self):
        (self.root / "pointers" / f"{self.key}.json").mkdir(parents=True)
        with self.assertRaises(StoreUnavailable):
            self.store.get_pointer(self.key)

    def test_a_blob_that_cannot_be_replaced_is_unavailable_and_leaves_no_temp_file(self):
        (self.root / "blobs" / DIGEST[:2] / DIGEST / "occupied").mkdir(parents=True)
        with self.assertRaises(StoreUnavailable):
            self.store.put_blob(DIGEST, DATA)
        self.assertEqual(self.leftovers(), [])

    def test_a_directory_that_cannot_be_created_is_unavailable(self):
        self.root.mkdir()
        (self.root / "blobs").write_text("a file where the blob directory should be", encoding="utf-8")
        with self.assertRaises(StoreUnavailable):
            self.store.put_blob(DIGEST, DATA)


if __name__ == "__main__":
    unittest.main()
