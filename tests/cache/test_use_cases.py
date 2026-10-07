import gzip
import os
import shutil
import tempfile
import threading
import unittest
from pathlib import Path

from support import PATCHED, DownStore, MemoryStore, device_info, file_info, key_for, link_info, publish, tar_bytes
from build_cache.adapters.fs_store import FilesystemStore
from build_cache.adapters.tar_archiver import TarArchiver, stamp_extracted
from build_cache.application.restore import restore
from build_cache.application.save import save
from build_cache.domain.models import ArchiveRejected, Manifest, StoreUnavailable
from build_cache.domain.policy import ExtractionRules, WriteDecision, write_decision

ALLOW = WriteDecision(True, "test")
STAMP = 2_000_000_000_000_000_000


class Workspace(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.src, self.dest = self.tmp / "src", self.tmp / "dest"
        (self.src / "obj").mkdir(parents=True)
        (self.src / "obj" / "a.dll").write_bytes(b"binary-a")
        (self.src / "obj" / "b.cache").write_text("cache")
        self.archiver = TarArchiver(prefer_zstd=False, version_info=PATCHED)


class RestoreSaveTests(Workspace):
    def test_roundtrip_hit_restores_exact_bytes(self):
        store, key = MemoryStore(), key_for("dotnet-outputs", "k")
        saved = save("dotnet-outputs", key, self.src, ["obj"], store, self.archiver, ALLOW)
        self.assertEqual(saved.status, "saved")
        hit = restore("dotnet-outputs", key, self.dest, store, self.archiver)
        self.assertEqual(hit.status, "hit")
        self.assertEqual((self.dest / "obj" / "a.dll").read_bytes(), b"binary-a")

    def test_outputs_are_never_restored_on_a_non_exact_key(self):
        store = MemoryStore()
        save("dotnet-outputs", key_for("dotnet-outputs", "old"), self.src, ["obj"], store, self.archiver, ALLOW)
        store.calls.clear()
        other = key_for("dotnet-outputs", "new")
        result = restore("dotnet-outputs", other, self.dest, store, self.archiver)
        self.assertEqual(result.status, "miss")
        self.assertEqual(store.calls, [("get_pointer", other)])
        self.assertFalse(self.dest.exists())

    def test_pointer_for_another_key_is_rejected(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW)
        other = key_for("nuget", "other")
        store.pointers[other] = store.pointers[key]
        self.assertEqual(restore("nuget", other, self.dest, store, self.archiver).status, "rejected")

    def test_digest_mismatch_is_rejected_and_extracts_nothing(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        real = self.archiver.pack(self.src, ["obj"]).data
        publish(store, key, "nuget", real + b"tampered", claimed_sha="0" * 64)
        result = restore("nuget", key, self.dest, store, self.archiver)
        self.assertEqual(result.status, "rejected")
        self.assertIn("digest", result.detail)
        self.assertFalse(self.dest.exists())

    def test_save_after_an_evicted_blob_replaces_the_pointer_and_the_next_restore_hits(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW)
        evicted = store.pointers[key].sha256
        store.blobs.clear()
        self.assertEqual(restore("nuget", key, self.dest, store, self.archiver).status, "miss")
        (self.src / "obj" / "a.dll").write_bytes(b"rebuilt")
        result = save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW, restored_verified_hit=False)
        self.assertEqual(result.status, "saved")
        self.assertNotEqual(store.pointers[key].sha256, evicted)
        self.assertEqual(list(store.blobs), [store.pointers[key].sha256])
        self.assertEqual(restore("nuget", key, self.dest, store, self.archiver).status, "hit")
        self.assertEqual((self.dest / "obj" / "a.dll").read_bytes(), b"rebuilt")

    def test_unreachable_store_is_a_miss_not_a_failure(self):
        for error in (StoreUnavailable("down"), TimeoutError("slow"), ConnectionResetError("reset")):
            result = restore("nuget", key_for("nuget", "k"), self.dest, DownStore(error), self.archiver)
            self.assertEqual(result.status, "miss", error)

    def test_unreachable_store_on_save_is_reported_not_raised(self):
        down = DownStore(TimeoutError("slow"))
        result = save("nuget", key_for("nuget", "k"), self.src, ["obj"], down, self.archiver, ALLOW)
        self.assertEqual(result.status, "unreachable")

    def test_save_is_skipped_only_when_this_job_restored_a_verified_hit(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW)
        before = dict(store.pointers)
        result = save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW, restored_verified_hit=True)
        self.assertEqual(result.status, "exists")
        self.assertEqual(store.pointers, before)
        self.assertEqual(save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW).status, "saved")

    def test_stamping_gives_every_restored_file_one_identical_time(self):
        store, key = MemoryStore(), key_for("dotnet-outputs", "k")
        save("dotnet-outputs", key, self.src, ["obj"], store, self.archiver, ALLOW)
        restore("dotnet-outputs", key, self.dest, store, self.archiver, lambda names: stamp_extracted(self.dest, names, STAMP))
        stamps = {p.stat().st_mtime_ns for p in (self.dest / "obj").iterdir()}
        self.assertEqual(stamps, {STAMP})

    def test_unstamped_restore_keeps_old_times_so_a_build_would_rerun(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW)
        restore("nuget", key, self.dest, store, self.archiver)
        self.assertLess((self.dest / "obj" / "a.dll").stat().st_mtime, 400_000_000)


class WritePolicyTests(Workspace):
    def test_decision_matrix(self):
        cases = [
            (True, "push", "refs/heads/master", True),
            (False, "push", "refs/heads/master", False),
            (True, "pull_request", "refs/heads/master", False),
            (True, "push", "refs/heads/feat/x", False),
            (True, "push", "refs/pull/3/merge", False),
            (True, "", "", False),
        ]
        for credential, event, ref, expected in cases:
            decision = write_decision(credential, event, ref, "master")
            self.assertEqual(decision.allowed, expected, (credential, event, ref))

    def test_refused_decision_writes_nothing(self):
        store = MemoryStore()
        decision = write_decision(False, "push", "refs/heads/master", "master")
        result = save("nuget", key_for("nuget", "k"), self.src, ["obj"], store, self.archiver, decision)
        self.assertEqual(result.status, "skipped")
        self.assertEqual(store.calls, [])


class ArchiveSafetyTests(Workspace):
    def reject(self, entries):
        store, key = MemoryStore(), key_for("nuget", "evil")
        publish(store, key, "nuget", gzip.compress(tar_bytes(entries)))
        result = restore("nuget", key, self.dest, store, self.archiver)
        self.assertEqual(result.status, "rejected", result.detail)
        self.assertFalse((self.tmp / "evil.txt").exists())

    def test_parent_traversal_refused(self):
        self.reject([(file_info("../evil.txt", 1), b"x")])

    def test_absolute_path_refused(self):
        self.reject([(file_info(str(self.tmp / "evil.txt"), 1), b"x")])

    def test_link_escaping_the_root_refused(self):
        self.reject([(link_info("pkg/escape", "../../evil.txt"), None)])

    def test_device_node_refused(self):
        self.reject([(device_info("dev0"), None)])

    def test_unpack_raises_archive_rejected(self):
        data = gzip.compress(tar_bytes([(file_info("../evil.txt", 1), b"x")]))
        with self.assertRaises(ArchiveRejected):
            self.archiver.unpack(data, "gzip", self.dest, ExtractionRules())

    def test_garbage_stream_refused(self):
        with self.assertRaises(ArchiveRejected):
            self.archiver.unpack(b"not gzip", "gzip", self.dest, ExtractionRules())

    def test_one_bad_member_means_nothing_is_extracted(self):
        entries = [(file_info("good.txt", 1), b"g"), (file_info("../evil.txt", 1), b"x")]
        with self.assertRaises(ArchiveRejected):
            self.archiver.unpack(gzip.compress(tar_bytes(entries)), "gzip", self.dest, ExtractionRules())
        self.assertFalse((self.dest / "good.txt").exists())


class ArchiverTests(Workspace):
    def test_pack_is_deterministic(self):
        first = self.archiver.pack(self.src, ["obj"]).data
        self.assertEqual(first, self.archiver.pack(self.src, ["obj"]).data)

    def test_pack_of_missing_path_is_none(self):
        self.assertIsNone(self.archiver.pack(self.src, ["absent"]))

    def test_pack_refuses_paths_outside_the_root(self):
        with self.assertRaises(ValueError):
            self.archiver.pack(self.src, ["../x"])

    @unittest.skipUnless(shutil.which("zstd"), "zstd binary not installed")
    def test_zstd_roundtrip_records_format(self):
        packed = TarArchiver(version_info=PATCHED).pack(self.src, ["obj"])
        self.assertEqual(packed.compression, "zstd")
        TarArchiver(version_info=PATCHED).unpack(packed.data, "zstd", self.dest, ExtractionRules())
        self.assertEqual((self.dest / "obj" / "a.dll").read_bytes(), b"binary-a")

    def test_gzip_used_when_zstd_absent_and_format_recorded(self):
        self.assertEqual(self.archiver.pack(self.src, ["obj"]).compression, "gzip")

    def test_manifest_records_the_format(self):
        store, key = MemoryStore(), key_for("nuget", "k")
        save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW)
        self.assertIsInstance(store.pointers[key], Manifest)
        self.assertEqual(store.pointers[key].compression, "gzip")


class FilesystemStoreTests(Workspace):
    def test_concurrent_save_of_one_key_leaves_one_complete_blob(self):
        store, key = FilesystemStore(self.tmp / "store"), key_for("nuget", "race")
        statuses, barrier = [], threading.Barrier(8)

        def worker():
            barrier.wait()
            statuses.append(save("nuget", key, self.src, ["obj"], store, self.archiver, ALLOW).status)

        threads = [threading.Thread(target=worker) for _ in range(8)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        blobs = [p for p in (self.tmp / "store" / "blobs").rglob("*") if p.is_file()]
        self.assertEqual(len(blobs), 1)
        self.assertEqual(list((self.tmp / "store").rglob(".tmp-*")), [])
        allowed = {"saved", "exists"} | ({"unreachable"} if os.name == "nt" else set())
        self.assertTrue(set(statuses) <= allowed, statuses)
        self.assertEqual(restore("nuget", key, self.dest, store, self.archiver).status, "hit")

    def test_malformed_key_is_refused(self):
        with self.assertRaises(ValueError):
            FilesystemStore(self.tmp).get_pointer("../../etc/passwd")

    def test_unknown_key_and_blob_are_none(self):
        store = FilesystemStore(self.tmp / "store")
        self.assertIsNone(store.get_pointer(key_for("nuget", "none")))
        self.assertIsNone(store.get_blob("0" * 64))


if __name__ == "__main__":
    unittest.main()
