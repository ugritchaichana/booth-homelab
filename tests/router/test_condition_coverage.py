import io
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import condition_coverage  # noqa: E402

SAMPLE = """
def both(a, b):
    return a and b


def pick(items, flag, stop):
    while flag:
        flag = False
    kept = [i for i in items if i > 1]
    return (kept or []) if not stop else None


if __name__ == "__main__":
    both(1, 2)
"""


def module(source):
    with tempfile.TemporaryDirectory() as d:
        path = Path(d) / "sample.py"
        path.write_text(source, encoding="utf-8")
        return condition_coverage.instrumented(path, "sample")


class ConditionCoverageTests(unittest.TestCase):
    def test_a_short_circuited_operand_is_reported(self):
        sample, sites, seen = module(SAMPLE)
        sample.both(True, True)
        sample.both(False, True)
        gaps = condition_coverage.missing(sites, seen)
        self.assertIn((3, "b", [True]), gaps)
        self.assertNotIn((3, "a", [False, True]), gaps)

    def test_loop_comprehension_negation_and_conditional_tests_are_sites(self):
        _, sites, _ = module(SAMPLE)
        texts = [text for _, text in sites]
        for expected in ("flag", "i > 1", "kept", "stop"):
            self.assertIn(expected, texts)
        self.assertEqual(texts.count("flag"), 1)

    def test_literals_and_the_main_guard_are_not_conditions(self):
        _, sites, _ = module(SAMPLE)
        texts = [text for _, text in sites]
        self.assertNotIn("[]", texts)
        self.assertFalse(any("__name__" in text for text in texts))

    def test_every_site_seen_both_ways_leaves_no_gap(self):
        sample, sites, seen = module(SAMPLE)
        for a, b in ((True, True), (True, False), (False, True)):
            sample.both(a, b)
        for items, flag, stop in (([0, 2], True, False), ([0], False, False), ([0], False, True)):
            sample.pick(items, flag, stop)
        self.assertEqual(condition_coverage.missing(sites, seen), [])

    def test_main_enforces_the_floor_and_the_test_result(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "target.py").write_text("def f(a, b):\n    return a and b\n", encoding="utf-8")
            tests = root / "tests"
            tests.mkdir()
            cases = {"half": "f(True, True)", "full": "f(True, True); f(True, False); f(False, True)", "red": "self.fail('red')"}
            outcomes = {}
            for name, body in cases.items():
                (tests / "test_target.py").write_text(
                    f"import unittest\nfrom target import f\n\n\nclass T(unittest.TestCase):\n    def test_{name}(self):\n        {body}\n",
                    encoding="utf-8")
                sys.modules.pop("test_target", None)
                out = io.StringIO()
                with redirect_stdout(out), redirect_stderr(io.StringIO()):
                    outcomes[name] = condition_coverage.main([str(root / "target.py"), str(tests)])
                outcomes[name + "_report"] = out.getvalue()
            sys.modules.pop("target", None)
            sys.modules.pop("test_target", None)
        self.assertEqual((outcomes["half"], outcomes["full"], outcomes["red"]), (1, 0, 1))
        self.assertIn("line 2: b seen only [True]", outcomes["half_report"])
        self.assertIn("conditions 2 of 2", outcomes["full_report"])


if __name__ == "__main__":
    unittest.main()
