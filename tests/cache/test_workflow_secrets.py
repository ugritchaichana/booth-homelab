import re
import unittest
from pathlib import Path

import yaml

import support

WORKFLOWS = support.REPO / ".github" / "workflows"
SECRETS = ("CACHE_WRITER_PASSWORD", "BUILD_CACHE_WRITER_TOKEN")
SAVE_ACTION = "./.github/actions/build-cache"
FALSY_BRANCH = re.compile(r"&&\s*(''|\"\")\s*\|\|")
WRITER_JOB = "    environment: cache-writer\n"


def is_save_step(step):
    return step.get("uses") == SAVE_ACTION and str((step.get("with") or {}).get("mode")) == "save"


def secret_violations(text):
    doc = yaml.safe_load(text)
    found = []
    allowed_total = 0
    for scope, env in [("workflow", doc.get("env"))] + [(f"job {name}", job.get("env")) for name, job in doc.get("jobs", {}).items()]:
        found += [f"{scope} env holds {key}" for key in SECRETS if key in (env or {})]
    for name, job in doc.get("jobs", {}).items():
        for step in job.get("steps", []):
            env = step.get("env") or {}
            held = [key for key in SECRETS if key in env]
            if not held:
                continue
            if is_save_step(step):
                allowed_total += sum(f"{k}{v}".count(secret) for k, v in env.items() for secret in SECRETS)
            else:
                found += [f"job {name} step {step.get('name')} holds {key} outside a client save step" for key in held]
    mentions = sum(text.count(key) for key in SECRETS)
    if mentions != allowed_total + len(found):
        found.append(f"{mentions - allowed_total - len(found)} mention(s) of a writer secret outside any step env")
    return found


def falsy_branch_hits(text):
    return FALSY_BRANCH.findall(text)


class WorkflowSecretTests(unittest.TestCase):
    def reusable(self):
        return (WORKFLOWS / "reusable-sdet-pipeline.yml").read_text(encoding="utf-8").replace("\r\n", "\n")

    def test_writer_secrets_appear_only_in_client_save_step_env(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            text = path.read_text(encoding="utf-8").replace("\r\n", "\n")
            with self.subTest(workflow=path.name):
                self.assertEqual(secret_violations(text), [])

    def test_save_steps_exist_so_the_check_is_not_vacuous(self):
        self.assertGreaterEqual(self.reusable().count("CACHE_WRITER_PASSWORD"), 3)

    def test_mutation_secret_moved_to_job_env_is_caught(self):
        mutated = self.reusable().replace(WRITER_JOB, WRITER_JOB + "    env:\n      CACHE_WRITER_PASSWORD: ${{ secrets.CACHE_WRITER_PASSWORD }}\n")
        self.assertNotEqual(mutated, self.reusable())
        self.assertTrue(secret_violations(mutated))

    def test_mutation_save_step_turned_into_restore_is_caught(self):
        mutated = self.reusable().replace("          mode: save\n", "          mode: restore\n", 1)
        self.assertNotEqual(mutated, self.reusable())
        self.assertTrue(secret_violations(mutated))

    def test_no_empty_string_on_the_true_side_of_an_and_or_ternary(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            with self.subTest(workflow=path.name):
                self.assertEqual(falsy_branch_hits(path.read_text(encoding="utf-8")), [])

    def test_mutation_inverted_ternary_is_caught(self):
        mutated = self.reusable().replace("&& 'http://10.99.17.10:8080' || ''", "&& '' || 'http://10.99.17.10:8080'")
        self.assertNotEqual(mutated, self.reusable())
        self.assertTrue(falsy_branch_hits(mutated))


if __name__ == "__main__":
    unittest.main()
