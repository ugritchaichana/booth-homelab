import unittest

import support  # noqa: F401
from build_cache.domain import keys
from build_cache.domain.models import Platform

PLATFORM = Platform("lxc-runner", "debian", "13", "x86_64")
LOCKS = {"apps/backend/a/packages.lock.json": "a" * 64, "apps/backend/b/packages.lock.json": "b" * 64}
TREES = {"apps/backend": "1" * 40, "apps/fixtures": "2" * 40}


def dep(platform=PLATFORM, toolchain="8.0.425", locks=LOCKS, namespace="nuget"):
    return keys.dependency_key(namespace, platform, toolchain, locks)


def out(platform=PLATFORM, sdk="8.0.425", configuration="Release", trees=TREES, root="/home/runner/work/repo"):
    return keys.outputs_key(platform, sdk, configuration, trees, root)


class DependencyKeyTests(unittest.TestCase):
    def test_stable_for_identical_input_and_input_order(self):
        self.assertEqual(dep(), dep())
        self.assertEqual(dep(locks=dict(reversed(list(LOCKS.items())))), dep())

    def test_changes_when_one_lockfile_byte_changes(self):
        changed = dict(LOCKS, **{"apps/backend/b/packages.lock.json": "b" * 63 + "c"})
        self.assertNotEqual(dep(locks=changed), dep())

    def test_changes_when_a_lockfile_is_added_removed_or_moved(self):
        self.assertNotEqual(dep(locks=dict(LOCKS, extra="c" * 64)), dep())
        self.assertNotEqual(dep(locks={"apps/backend/a/packages.lock.json": "a" * 64}), dep())
        moved = {"apps/backend/z/packages.lock.json": "a" * 64, "apps/backend/b/packages.lock.json": "b" * 64}
        self.assertNotEqual(dep(locks=moved), dep())

    def test_changes_with_toolchain_and_every_platform_field(self):
        self.assertNotEqual(dep(toolchain="8.0.426"), dep())
        for field, value in (("runner_class", "vm-docker"), ("os_id", "ubuntu"), ("os_version", "14"), ("arch", "aarch64")):
            other = Platform(**{**PLATFORM.__dict__, field: value})
            self.assertNotEqual(dep(platform=other), dep(), field)

    def test_namespaces_never_share_a_key(self):
        self.assertNotEqual(dep(namespace="nuget"), dep(namespace="node_modules"))

    def test_rejects_empty_lockfile_set_and_unknown_namespace(self):
        with self.assertRaises(ValueError):
            dep(locks={})
        with self.assertRaises(ValueError):
            dep(namespace="dotnet-outputs")

    def test_key_shape(self):
        self.assertRegex(dep(), r"^nuget-[0-9a-f]{64}$")


class OutputsKeyTests(unittest.TestCase):
    def test_stable(self):
        self.assertEqual(out(), out())
        self.assertEqual(out(trees=dict(reversed(list(TREES.items())))), out())

    def test_changes_when_any_tree_id_changes(self):
        for path in TREES:
            self.assertNotEqual(out(trees=dict(TREES, **{path: "3" * 40})), out(), path)

    def test_changes_with_sdk_configuration_and_platform(self):
        self.assertNotEqual(out(sdk="8.0.426"), out())
        self.assertNotEqual(out(configuration="Debug"), out())
        self.assertNotEqual(out(platform=Platform("vm-docker", "debian", "13", "x86_64")), out())

    def test_changes_when_the_workspace_root_changes(self):
        self.assertNotEqual(out(root="/home/runner/work/other"), out())

    def test_entries_saved_under_the_first_outputs_schema_are_unreachable(self):
        first = {"schema": 1, "namespace": keys.OUTPUT_KIND, "platform": keys._platform_record(PLATFORM), "toolchain": "8.0.425",
                 "configuration": "Release", "workspace_root": "/home/runner/work/repo", "trees": keys._sorted_pairs(TREES)}
        self.assertNotEqual(out(), f"{keys.OUTPUT_KIND}-{keys.digest(first)}")

    def test_rejects_empty_trees(self):
        with self.assertRaises(ValueError):
            out(trees={})


class ShortKeyTests(unittest.TestCase):
    def test_is_the_first_twelve_hex_of_the_digest_after_the_kind_prefix(self):
        for key in (dep(), out()):
            self.assertEqual(keys.short_key(key), key.rsplit("-", 1)[1][:12])

    def test_uses_only_the_last_sixty_four_characters(self):
        self.assertEqual(keys.short_key("x" * 30 + "ab" * 32), "ab" * 6)

    def test_outcome_records_carry_the_same_short_key(self):
        from build_cache.application.ports import Outcome

        key = dep()
        self.assertEqual(Outcome("restore", "nuget", key, "hit", 0, 0).as_record()["key"], keys.short_key(key))


if __name__ == "__main__":
    unittest.main()
