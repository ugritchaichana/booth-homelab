import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
PIPELINE = REPO / ".github" / "workflows" / "reusable-sdet-pipeline.yml"
REPORT = REPO / "scripts" / "ci" / "sdet-report.sh"
TEST_JOBS = {"dotnet-unit": ("unit", "affected-unit.txt"), "dotnet-integration": ("integration", "affected-integration.txt")}
TEST_BINARIES = "dotnet-test-bin"


def steps_using(job, action):
    return [s for s in job.get("steps", []) if str(s.get("uses", "")).startswith(action)]


def split_problems(pipeline_text, report_text):
    jobs = yaml.safe_load(pipeline_text)["jobs"]
    found = []
    uploaded = [s["with"]["name"] for s in steps_using(jobs["dotnet"], "actions/upload-artifact")]
    if TEST_BINARIES not in uploaded:
        found.append("the build job does not upload the test binaries")
    for name, (kind, list_file) in TEST_JOBS.items():
        job = jobs.get(name, {})
        if "dotnet" not in job.get("needs", []):
            found.append(f"{name} does not wait for the build")
        if f"needs.dotnet.outputs.{kind}_count != '0'" not in str(job.get("if")):
            found.append(f"{name} does not skip when no {kind} suite is affected")
        if [s["with"]["name"] for s in steps_using(job, "actions/download-artifact")] != [TEST_BINARIES]:
            found.append(f"{name} does not download the test binaries")
        runs = " ".join(str(s.get("run", "")) for s in job.get("steps", []))
        if f"dotnet-run-tests.sh {list_file}" not in runs:
            found.append(f"{name} does not run its own list")
        results = [s["with"]["name"] for s in steps_using(job, "actions/upload-artifact")]
        if results != [f"sdet-dotnet-{kind}-results"]:
            found.append(f"{name} uploads {results}")
        elif results[0] not in report_text:
            found.append(f"the report does not download {results[0]}")
        if name not in jobs["summary"].get("needs", []):
            found.append(f"the report job does not wait for {name}")
        if f"needs.{name}.result" not in str(jobs["summary"].get("env")):
            found.append(f"the report job does not read the result of {name}")
    outputs = jobs["dotnet"].get("outputs", {})
    for kind in ("unit", "integration"):
        if outputs.get(f"{kind}_count") != f"${{{{ steps.select.outputs.{kind}_count }}}}":
            found.append(f"the build job does not expose {kind}_count")
    return found


class PipelineSplitTests(unittest.TestCase):
    def texts(self):
        return PIPELINE.read_text(encoding="utf-8").replace("\r\n", "\n"), REPORT.read_text(encoding="utf-8")

    def test_unit_and_integration_run_as_their_own_jobs_on_the_built_binaries(self):
        self.assertEqual(split_problems(*self.texts()), [])

    def test_mutants_of_the_split_are_caught(self):
        pipeline, report = self.texts()
        mutants = {
            "integration result not reported": (pipeline, report.replace("sdet-dotnet-integration-results ", "")),
            "unit job without the binaries": (pipeline.replace("          name: dotnet-test-bin\n          path: ${{ github.workspace }}\n", "          name: other\n          path: ${{ github.workspace }}\n", 1), report),
            "report ignores the integration job": (pipeline.replace("dotnet-unit, dotnet-integration, dotnet-cache-save", "dotnet-unit, dotnet-cache-save"), report),
            "unit job runs the integration list": (pipeline.replace("dotnet-run-tests.sh affected-unit.txt", "dotnet-run-tests.sh affected-integration.txt"), report),
            "integration job never skips": (pipeline.replace("    if: needs.dotnet.outputs.integration_count != '0'\n", ""), report),
        }
        for name, (mutated_pipeline, mutated_report) in mutants.items():
            with self.subTest(name):
                self.assertNotEqual((mutated_pipeline, mutated_report), (pipeline, report))
                self.assertTrue(split_problems(mutated_pipeline, mutated_report))


if __name__ == "__main__":
    unittest.main()
