import re
import unittest

import yaml

import support

REUSABLE = support.REPO / ".github" / "workflows" / "reusable-sdet-pipeline.yml"
DOWNLOAD = "actions/download-artifact@"
UPLOAD = "actions/upload-artifact@"
SKIP_WHEN_TRUE = re.compile(r"steps\.([\w-]+)\.outputs\.([\w-]+) != 'true'")


def ungated_saves(text):
    jobs = yaml.safe_load(text)["jobs"]
    uploads = {}
    for name, job in jobs.items():
        for step in job.get("steps", []):
            if str(step.get("uses", "")).startswith(UPLOAD):
                uploads[step["with"]["name"]] = (name, step.get("if") or "")
    found = []
    for name, job in jobs.items():
        for step in job.get("steps", []):
            if not str(step.get("uses", "")).startswith(DOWNLOAD):
                continue
            producer, condition = uploads[step["with"]["name"]]
            outputs = jobs[producer].get("outputs") or {}
            for step_id, output in SKIP_WHEN_TRUE.findall(condition):
                keys = [k for k, v in outputs.items() if f"steps.{step_id}.outputs.{output}" in str(v)]
                if not any(f"needs.{producer}.outputs.{k} != 'true'" in str(job.get("if")) for k in keys):
                    found.append(f"job {name} downloads {step['with']['name']} even when {producer} skips the upload on {output}")
    return found


class SaveGateTests(unittest.TestCase):
    def reusable(self):
        return REUSABLE.read_text(encoding="utf-8").replace("\r\n", "\n")

    def test_a_save_job_runs_only_when_its_payload_was_uploaded(self):
        self.assertEqual(ungated_saves(self.reusable()), [])

    def test_both_payload_downloads_are_seen_so_the_check_is_not_vacuous(self):
        self.assertEqual(self.reusable().count(DOWNLOAD), 2)

    def test_mutation_dropped_hit_gate_is_caught(self):
        text = self.reusable()
        mutated = text.replace(" && needs.angular-jest.outputs.cache_hit_node_modules != 'true'", "")
        self.assertNotEqual(mutated, text)
        self.assertTrue(ungated_saves(mutated))


if __name__ == "__main__":
    unittest.main()
