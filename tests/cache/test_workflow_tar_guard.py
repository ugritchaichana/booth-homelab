import re
import unittest

import yaml

import support

REUSABLE = support.REPO / ".github" / "workflows" / "reusable-sdet-pipeline.yml"
EXTRACT = re.compile(r"tar\b[^\n]*\s-xf\s+(\"[^\"]+\"|\S+)")
CHECKS = ('tar -tf "$1"', 'tar -tvf "$1"', r"\.\.", "bad=1")


def unguarded_extractions(text):
    found = []
    for name, job in yaml.safe_load(text).get("jobs", {}).items():
        for step in job.get("steps", []):
            script = step.get("run") or ""
            for match in EXTRACT.finditer(script):
                archive = match.group(1)
                before = script[: match.start()]
                missing = [check for check in CHECKS if check not in before]
                if missing or f"verify_members {archive} " not in before:
                    found.append(f"job {name} step {step.get('name')} extracts {archive} without a complete member check")
    return found


def extraction_count(text):
    return sum(len(EXTRACT.findall(step.get("run") or "")) for job in yaml.safe_load(text).get("jobs", {}).values() for step in job.get("steps", []))


class TarGuardTests(unittest.TestCase):
    def reusable(self):
        return REUSABLE.read_text(encoding="utf-8").replace("\r\n", "\n")

    def test_every_extraction_is_preceded_by_a_member_check(self):
        self.assertEqual(unguarded_extractions(self.reusable()), [])

    def test_all_three_payload_extractions_are_seen_so_the_check_is_not_vacuous(self):
        self.assertEqual(extraction_count(self.reusable()), 3)

    def test_mutation_removed_call_is_caught(self):
        text = self.reusable()
        mutated = re.sub(r"^\s*verify_members \S+ .*\n", "", text, flags=re.M)
        self.assertNotEqual(mutated, text)
        self.assertTrue(unguarded_extractions(mutated))

    def test_mutation_removed_link_check_is_caught(self):
        text = self.reusable()
        mutated = text.replace('tar -tvf "$1"', 'true "$1"')
        self.assertNotEqual(mutated, text)
        self.assertTrue(unguarded_extractions(mutated))


if __name__ == "__main__":
    unittest.main()
