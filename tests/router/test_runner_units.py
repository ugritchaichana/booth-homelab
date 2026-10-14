import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
TEMPLATES = REPO / "iac" / "ansible" / "playbooks" / "templates"
RUNNER_DIR = "{{ ci_runner_dir }}"


def path_problems(unit):
    service = dict(re.findall(r"^(BindPaths|WorkingDirectory|ExecStart)=(.*)$", unit, re.M))
    found = []
    if service.get("BindPaths") != f"{RUNNER_DIR}-%i:{RUNNER_DIR}":
        found.append("the instance directory is not bound to the shared runner path")
    if service.get("WorkingDirectory") != RUNNER_DIR:
        found.append("the working directory is not the shared runner path")
    if service.get("ExecStart") != f"{RUNNER_DIR}/run.sh":
        found.append("the runner does not start from the shared runner path")
    return found


class RunnerUnitTests(unittest.TestCase):
    def unit(self):
        return (TEMPLATES / "actions-runner@.service.j2").read_text(encoding="utf-8").replace("\r\n", "\n")

    def test_every_instance_runs_from_one_shared_path(self):
        self.assertEqual(path_problems(self.unit()), [])

    def test_mutants_that_start_an_instance_from_its_own_path_are_caught(self):
        text = self.unit()
        mutants = {
            "instance start path": text.replace(f"ExecStart={RUNNER_DIR}/run.sh", f"ExecStart={RUNNER_DIR}-%i/run.sh"),
            "instance working directory": text.replace(f"WorkingDirectory={RUNNER_DIR}\n", f"WorkingDirectory={RUNNER_DIR}-%i\n"),
            "no bind": text.replace(f"BindPaths={RUNNER_DIR}-%i:{RUNNER_DIR}\n", ""),
        }
        for name, mutated in mutants.items():
            with self.subTest(name):
                self.assertNotEqual(mutated, text)
                self.assertTrue(path_problems(mutated))

    def test_the_restart_unit_no_longer_passes_a_runner_root(self):
        restart = (TEMPLATES / "actions-runner-restart@.service.j2").read_text(encoding="utf-8")
        self.assertNotIn("RUNNER_ROOT", restart)


if __name__ == "__main__":
    unittest.main()
