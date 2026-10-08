import unittest

import yaml

import support

REUSABLE = support.REPO / ".github" / "workflows" / "reusable-sdet-pipeline.yml"
BUILD_ROOT = "${{ needs.dotnet.outputs.workspace }}"


def outputs_key_wiring(text):
    jobs = yaml.safe_load(text)["jobs"]
    found = []
    if jobs["dotnet"].get("outputs", {}).get("workspace") != "${{ github.workspace }}":
        found.append("job dotnet does not expose its workspace")
    saves = [s for s in jobs["dotnet-cache-save"]["steps"] if (s.get("with") or {}).get("kind") == "dotnet-outputs" and (s.get("with") or {}).get("mode") == "save"]
    if len(saves) != 1:
        found.append(f"expected one dotnet-outputs save step, found {len(saves)}")
    elif (saves[0].get("env") or {}).get("BUILD_CACHE_KEY_ROOT") != BUILD_ROOT:
        found.append("the dotnet-outputs save is not keyed by the build workspace")
    return found


class OutputsKeyWiringTests(unittest.TestCase):
    def reusable(self):
        return REUSABLE.read_text(encoding="utf-8").replace("\r\n", "\n")

    def test_the_outputs_save_is_keyed_by_the_workspace_that_built_them(self):
        self.assertEqual(outputs_key_wiring(self.reusable()), [])

    def test_mutation_dropped_key_root_is_caught(self):
        text = self.reusable()
        mutated = text.replace(f"          BUILD_CACHE_KEY_ROOT: {BUILD_ROOT}\n", "")
        self.assertNotEqual(mutated, text)
        self.assertTrue(outputs_key_wiring(mutated))


if __name__ == "__main__":
    unittest.main()
