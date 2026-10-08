import re
import unittest
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
WORKFLOWS = REPO / ".github" / "workflows"
PIPELINE = "reusable-sdet-pipeline.yml"
TOKEN = "RUNNER_STATUS_TOKEN"
ROUTE_STEP = "Decide Runner Class"
ROUTED_ENV = ("CACHE_URL", "BUILD_CACHE_RUNNER_CLASS")
HOSTED_OUTPUT = "needs.select-runner.outputs.hosted != 'true'"
ROUTER_PERMISSIONS = {"actions": "read", "checks": "read", "contents": "read"}


def read(name):
    return (WORKFLOWS / name).read_text(encoding="utf-8").replace("\r\n", "\n")


def token_violations(name, text):
    doc = yaml.safe_load(text)
    allowed = 0
    if name == PIPELINE:
        for step in doc["jobs"]["select-runner"]["steps"]:
            if step.get("name") == ROUTE_STEP:
                allowed += (step.get("env") or {}).get(TOKEN) == "${{ secrets.%s }}" % TOKEN
    mentions = len(re.findall(TOKEN, text))
    expected = 1 if name == PIPELINE else 0
    found = []
    if allowed != expected:
        found.append(f"{name}: the route step reads the token {allowed} time(s), expected {expected}")
    if mentions != 2 * expected:
        found.append(f"{name}: {mentions} mention(s) of {TOKEN}, expected {2 * expected}")
    return found


def routed_env_violations(text):
    doc = yaml.safe_load(text)
    found = [f"workflow env sets {key}" for key in ROUTED_ENV if key in (doc.get("env") or {})]
    for name, job in doc["jobs"].items():
        for key, value in (job.get("env") or {}).items():
            if key in ROUTED_ENV and (HOSTED_OUTPUT not in str(value) or "select-runner" not in job.get("needs", [])):
                found.append(f"job {name} sets {key} without the route")
        if "fromJSON(needs.select-runner" in str(job.get("runs-on")) and "CACHE_URL" not in (job.get("env") or {}):
            found.append(f"job {name} runs on the routed runner without CACHE_URL")
    return found


def callers():
    return [p.name for p in sorted(WORKFLOWS.glob("*.yml")) if f"./.github/workflows/{PIPELINE}" in read(p.name)]


class RouterWorkflowTests(unittest.TestCase):
    def test_the_status_token_is_declared_and_read_only_by_the_route_step(self):
        for path in sorted(WORKFLOWS.glob("*.yml")):
            with self.subTest(workflow=path.name):
                self.assertEqual(token_violations(path.name, read(path.name)), [])

    def test_mutation_token_moved_to_job_env_is_caught(self):
        text = read(PIPELINE)
        mutated = text.replace("    permissions:\n      actions: read\n      checks: read\n",
                               f"    env:\n      {TOKEN}: ${{{{ secrets.{TOKEN} }}}}\n    permissions:\n      actions: read\n      checks: read\n", 1)
        self.assertNotEqual(mutated, text)
        self.assertTrue(token_violations(PIPELINE, mutated))

    def test_mutation_token_read_by_another_workflow_is_caught(self):
        text = read("sdet-callback.yml")
        mutated = text.replace("GH_TOKEN: ${{ github.token }}", f"GH_TOKEN: ${{{{ secrets.{TOKEN} }}}}", 1)
        self.assertNotEqual(mutated, text)
        self.assertTrue(token_violations("sdet-callback.yml", mutated))

    def test_the_route_job_has_only_read_permissions(self):
        job = yaml.safe_load(read(PIPELINE))["jobs"]["select-runner"]
        self.assertEqual(job["permissions"], ROUTER_PERMISSIONS)
        checkout = job["steps"][0]["with"]
        self.assertEqual((checkout["persist-credentials"], checkout["sparse-checkout"]), (False, "scripts/ci"))

    def test_every_caller_grants_what_the_route_job_asks_for(self):
        self.assertEqual(callers(), ["sdet-ci.yml", "sdet-fallback-drill.yml"])
        for name in callers():
            with self.subTest(workflow=name):
                granted = yaml.safe_load(read(name)).get("permissions") or {}
                self.assertEqual({k: granted.get(k) for k in ROUTER_PERMISSIONS}, ROUTER_PERMISSIONS)

    def test_cache_endpoint_follows_the_route_not_the_input(self):
        self.assertEqual(routed_env_violations(read(PIPELINE)), [])

    def test_mutation_cache_endpoint_back_on_the_input_is_caught(self):
        text = read(PIPELINE)
        mutated = text.replace("  NUGET_PACKAGES:", "  CACHE_URL: ${{ !inputs.force_ubuntu_runner && 'http://10.99.17.10:8080' || '' }}\n  NUGET_PACKAGES:", 1)
        self.assertNotEqual(mutated, text)
        self.assertTrue(routed_env_violations(mutated))

    def test_mutation_routed_job_without_the_cache_env_is_caught(self):
        text = read(PIPELINE)
        mutated = re.sub(r"(  telemetry:\n(?:.*\n)*?)    env:\n      CACHE_URL: .*\n", r"\1", text, count=1)
        self.assertNotEqual(mutated, text)
        self.assertTrue(routed_env_violations(mutated))


if __name__ == "__main__":
    unittest.main()
