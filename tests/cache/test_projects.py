import unittest

import support  # noqa: F401
from build_cache.domain.projects import Project, ancestors, closure, key_inputs, shared_files

DOMAIN = Project("apps/backend/src/Domain/Domain.csproj")
APP = Project("apps/backend/src/App/App.csproj", ("apps/backend/src/Domain/Domain.csproj",))
API = Project("apps/backend/src/Api/Api.csproj", ("apps/backend/src/App/App.csproj",))
TESTS = Project("apps/backend/tests/Api.Tests/Api.Tests.csproj", ("apps/backend/src/Api/Api.csproj",), ("apps/fixtures/cases.json",))
GRAPH = {p.path: p for p in (DOMAIN, APP, API, TESTS)}
TRACKED = [
    "Directory.Build.props",
    "apps/backend/Directory.Build.props",
    "apps/backend/Solution.sln",
    "apps/backend/src/Api/Directory.Build.targets",
    "apps/backend/src/Api/Program.cs",
    "apps/backend/tests/Api.Tests/global.json",
    "apps/frontend/Directory.Build.props",
    "docs/NuGet.Config",
]


class ClosureTests(unittest.TestCase):
    def test_a_project_without_references_is_its_own_closure(self):
        self.assertEqual(closure(GRAPH, DOMAIN.path), [DOMAIN])

    def test_the_closure_follows_references_transitively_in_path_order(self):
        self.assertEqual(closure(GRAPH, TESTS.path), [API, APP, DOMAIN, TESTS])

    def test_a_reference_cycle_ends(self):
        a = Project("a/A.csproj", ("b/B.csproj",))
        b = Project("b/B.csproj", ("a/A.csproj",))
        self.assertEqual(closure({a.path: a, b.path: b}, a.path), [a, b])

    def test_a_diamond_lists_the_shared_project_once(self):
        left = Project("l/L.csproj", (DOMAIN.path,))
        right = Project("r/R.csproj", (DOMAIN.path,))
        top = Project("t/T.csproj", (left.path, right.path))
        graph = {p.path: p for p in (DOMAIN, left, right, top)}
        self.assertEqual(closure(graph, top.path), [DOMAIN, left, right, top])

    def test_a_reference_outside_the_inputs_cannot_be_keyed(self):
        with self.assertRaisesRegex(ValueError, "not a project under the input paths"):
            closure({APP.path: APP}, APP.path)

    def test_an_unreadable_member_makes_every_dependent_unkeyable_and_leaves_others_keyable(self):
        graph = dict(GRAPH, **{APP.path: ValueError("uses an MSBuild expansion")})
        with self.assertRaisesRegex(ValueError, "App.csproj cannot be keyed: uses an MSBuild expansion"):
            closure(graph, TESTS.path)
        self.assertEqual(closure(graph, DOMAIN.path), [DOMAIN])


class SharedFilesTests(unittest.TestCase):
    def test_ancestors_run_from_the_directory_up_to_the_repository_root(self):
        self.assertEqual(ancestors("apps/backend/src"), {"apps/backend/src", "apps/backend", "apps", ""})
        self.assertEqual(ancestors(""), {""})

    def test_only_build_files_in_the_directory_or_above_count_whatever_their_case(self):
        self.assertEqual(
            shared_files(TRACKED, "apps/backend/src/Api"),
            ["Directory.Build.props", "apps/backend/Directory.Build.props", "apps/backend/src/Api/Directory.Build.targets"],
        )

    def test_build_files_in_a_sibling_or_below_do_not_count(self):
        self.assertEqual(shared_files(TRACKED, "apps/backend/src/Domain"), ["Directory.Build.props", "apps/backend/Directory.Build.props"])
        self.assertEqual(shared_files(TRACKED, "docs"), ["Directory.Build.props", "docs/NuGet.Config"])


class KeyInputsTests(unittest.TestCase):
    def test_a_leaf_project_is_keyed_by_its_directory_and_the_build_files_above_it(self):
        self.assertEqual(
            key_inputs(GRAPH, DOMAIN.path, TRACKED),
            ["Directory.Build.props", "apps/backend/Directory.Build.props", "apps/backend/src/Domain"],
        )

    def test_a_test_project_is_keyed_by_its_whole_closure_its_extra_inputs_and_each_members_build_files(self):
        self.assertEqual(
            key_inputs(GRAPH, TESTS.path, TRACKED),
            [
                "Directory.Build.props",
                "apps/backend/Directory.Build.props",
                "apps/backend/src/Api",
                "apps/backend/src/Api/Directory.Build.targets",
                "apps/backend/src/App",
                "apps/backend/src/Domain",
                "apps/backend/tests/Api.Tests",
                "apps/backend/tests/Api.Tests/global.json",
                "apps/fixtures/cases.json",
            ],
        )

    def test_the_inputs_of_a_dependency_never_include_its_dependents(self):
        self.assertNotIn("apps/backend/src/Api", key_inputs(GRAPH, APP.path, TRACKED))

    def test_a_project_at_the_repository_root_is_keyed_by_the_whole_tree(self):
        root = Project("Root.csproj")
        self.assertEqual(root.directory, "")
        self.assertEqual(key_inputs({root.path: root}, root.path, TRACKED), ["", "Directory.Build.props"])


if __name__ == "__main__":
    unittest.main()
