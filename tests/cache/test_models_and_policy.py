import json
import unittest

from support import key_for
from build_cache.domain.models import Manifest, ManifestError
from build_cache.domain.policy import ExtractionRules, member_allowed, write_decision

KEY = key_for("nuget", "model")
DIGEST = "a" * 64


def manifest(**overrides):
    fields = {"key": KEY, "kind": "nuget", "sha256": DIGEST, "size": 3, "compression": "gzip"}
    return Manifest(**{**fields, **overrides})


class ManifestValidationTests(unittest.TestCase):
    def test_a_well_formed_manifest_round_trips_through_json(self):
        self.assertEqual(Manifest.from_json(manifest().to_json()), manifest())

    def test_a_key_without_a_trailing_digest_is_refused(self):
        with self.assertRaisesRegex(ManifestError, "malformed key"):
            manifest(key="nuget-latest")

    def test_a_blob_digest_that_is_not_64_lowercase_hex_is_refused(self):
        for digest in ("abc", "A" * 64, "g" * 64):
            with self.assertRaisesRegex(ManifestError, "malformed blob digest", msg=digest):
                manifest(sha256=digest)

    def test_a_compression_other_than_zstd_or_gzip_is_refused(self):
        with self.assertRaisesRegex(ManifestError, "unknown compression"):
            manifest(compression="lz4")

    def test_a_size_that_is_not_a_non_negative_integer_is_refused(self):
        for size in ("3", 2.5, None, -1):
            with self.assertRaisesRegex(ManifestError, "malformed size", msg=repr(size)):
                manifest(size=size)

    def test_zero_is_an_acceptable_size(self):
        self.assertEqual(manifest(size=0).size, 0)


class ManifestParsingTests(unittest.TestCase):
    def valid(self, **overrides):
        return json.dumps({"key": KEY, "kind": "nuget", "sha256": DIGEST, "size": 3, "compression": "gzip", **overrides})

    def test_text_that_is_not_json_is_an_unreadable_manifest(self):
        with self.assertRaisesRegex(ManifestError, "unreadable manifest"):
            Manifest.from_json("{not json")

    def test_a_missing_field_is_an_unreadable_manifest(self):
        raw = json.loads(self.valid())
        del raw["sha256"]
        with self.assertRaisesRegex(ManifestError, "unreadable manifest"):
            Manifest.from_json(json.dumps(raw))

    def test_json_that_is_not_an_object_is_an_unreadable_manifest(self):
        for text in ("[]", "null", "3"):
            with self.assertRaisesRegex(ManifestError, "unreadable manifest", msg=text):
                Manifest.from_json(text)

    def test_a_field_failing_validation_keeps_its_own_message(self):
        with self.assertRaisesRegex(ManifestError, "malformed key"):
            Manifest.from_json(self.valid(key="nuget-latest"))

    def test_a_size_given_as_a_string_is_refused(self):
        with self.assertRaisesRegex(ManifestError, "malformed size"):
            Manifest.from_json(self.valid(size="3"))


class WriteDecisionReasonTests(unittest.TestCase):
    def test_a_push_with_no_ref_is_refused_and_says_so(self):
        decision = write_decision(True, "push", "", "master")
        self.assertEqual((decision.allowed, decision.reason), (False, "ref (none) is not the default branch"))

    def test_a_missing_event_is_refused_and_says_so(self):
        decision = write_decision(True, "", "refs/heads/master", "master")
        self.assertEqual((decision.allowed, decision.reason), (False, "event (none) is not a push"))


class MemberPolicyEdgeTests(unittest.TestCase):
    def test_a_member_name_with_no_path_parts_is_never_allowed(self):
        for name in ("", ".", "./."):
            self.assertFalse(member_allowed(name, ExtractionRules()), name)


if __name__ == "__main__":
    unittest.main()
