#!/usr/bin/env python3
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

SCORER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scorecard.py")
TODAY = "2026-10-06"
FRESH_DATE = "2026-10-01"
STALE_DATE = "2026-06-01"
LONG_EXPIRY = "2027-01-04"
GIT_IDENTITY = ["-c", "user.name=fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.autocrlf=false"]
BLOCKING_HEADER = "| condition | status | note | date |\n|---|---|---|---|\n"


def remove_tree(path):
    def force(func, target, *_):
        os.chmod(target, stat.S_IWRITE)
        func(target)

    option = {"onexc": force} if sys.version_info >= (3, 12) else {"onerror": force}
    shutil.rmtree(path, **option)


class ScorecardFixture(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(remove_tree, self.root)
        self.git("init", "-q")
        self.rows = []
        self.write("src/covered.txt", "one\n")
        self.write("src/other.txt", "one\n")
        self.first_sha = self.commit("seed")

    def git(self, *args):
        result = subprocess.run(["git", *GIT_IDENTITY, *args], cwd=self.root, capture_output=True, text=True, check=True)
        return result.stdout.strip()

    def write(self, relative, text):
        path = os.path.join(self.root, *relative.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def add_criterion(self, criterion_id, covered="-", check="-"):
        self.rows.append("\t".join([criterion_id, "axis", f"name {criterion_id}", "ci", covered, check]))

    def add_record(self, criterion_id, date, sha, score, expires=None):
        expires = expires or f"{LONG_EXPIRY} or on change to covered paths"
        self.write(
            f"standard/evidence/{criterion_id}/{date}.md",
            f"# {criterion_id} - fixture\n- Date / Commit: {date} / {sha}\n- Measured by: fixture\n- Procedure: none\n"
            f"- Raw output:\n```\nnone\n```\n- Result: score {score} - met: x - missing: none\n- Expires: {expires}\n",
        )

    def add_ack(self, criterion_id, date):
        self.write(f"standard/evidence/{criterion_id}/{date}-ack.md", f"# {criterion_id} - acknowledged drop\n")

    def set_blocking(self, *statuses):
        body = "".join(f"| condition {index} | {status} | note | 2026-10-06 |\n" for index, status in enumerate(statuses))
        self.write("standard/blocking.md", BLOCKING_HEADER + body)

    def run_scorer(self, today=TODAY):
        self.write("standard/criteria.tsv", "\n".join(self.rows) + "\n")
        if not os.path.exists(os.path.join(self.root, "standard", "blocking.md")):
            self.set_blocking("closed")
        env = {key: value for key, value in os.environ.items() if key != "GITHUB_STEP_SUMMARY"}
        env["SCORECARD_TODAY"] = today
        result = subprocess.run([sys.executable, SCORER], cwd=self.root, capture_output=True, text=True, env=env)
        return result.returncode, self.parse_rows(result.stdout), result.stdout + result.stderr

    @staticmethod
    def parse_rows(stdout):
        rows = {}
        for line in stdout.splitlines():
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if line.startswith("| ") and len(cells) == 6 and cells[0] not in ("id", "---"):
                rows[cells[0]] = {"recorded": cells[2], "current": cells[3], "state": cells[4], "check": cells[5]}
        return rows


class ScorecardRules(ScorecardFixture):
    def test_fresh_record_keeps_its_score(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        code, rows, out = self.run_scorer()
        self.assertEqual(code, 0, out)
        self.assertEqual(rows["4.3"]["current"], "2")
        self.assertEqual(rows["4.3"]["state"], "fresh")

    def test_record_older_than_ninety_days_scores_zero(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", STALE_DATE, self.first_sha, 2, expires="2026-08-30 or on change to src/covered.txt")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertTrue(rows["4.3"]["state"].startswith("expired: date"), out)

    def test_expiry_defaults_to_ninety_days_when_the_record_names_no_date(self):
        self.add_criterion("4.3")
        self.add_record("4.3", STALE_DATE, self.first_sha, 2, expires="on change to nothing")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertIn("2026-08-30", rows["4.3"]["state"])

    def test_covered_path_change_scores_zero_and_unrelated_change_does_not(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        self.write("src/other.txt", "two\n")
        self.commit("touch an uncovered file")
        _, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "2", out)
        self.write("src/covered.txt", "two\n")
        self.commit("touch the covered file")
        _, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertIn("covered path changed", rows["4.3"]["state"])

    def test_missing_commit_scores_zero(self):
        self.add_criterion("4.3")
        self.add_record("4.3", FRESH_DATE, "0123456789abcdef0123456789abcdef01234567", 2)
        _, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertIn("commit missing", rows["4.3"]["state"])

    def test_drop_without_acknowledgement_fails_the_run(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        self.write("src/covered.txt", "two\n")
        self.commit("touch the covered file")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertEqual(code, 1, out)
        self.assertIn("Ratchet violations", out)

    def test_drop_with_acknowledgement_passes_the_run(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        self.add_ack("4.3", "2026-10-05")
        self.write("src/covered.txt", "two\n")
        self.commit("touch the covered file")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertEqual(code, 0, out)

    def test_acknowledgement_older_than_the_record_does_not_count(self):
        self.add_criterion("4.3", covered="src/covered.txt")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        self.add_ack("4.3", "2026-09-01")
        self.write("src/covered.txt", "two\n")
        self.commit("touch the covered file")
        code, _, out = self.run_scorer()
        self.assertEqual(code, 1, out)

    def test_open_blocking_condition_caps_the_composite_at_49(self):
        for index in range(13):
            criterion_id = f"9.{index}"
            self.add_criterion(criterion_id)
            self.add_record(criterion_id, FRESH_DATE, self.first_sha, 2)
        self.set_blocking("open", "closed")
        code, _, out = self.run_scorer()
        self.assertEqual(code, 0, out)
        self.assertIn("Composite: 49 / 100", out)
        self.assertIn("REJECTED", out)
        self.set_blocking("closed", "closed")
        _, _, out = self.run_scorer()
        self.assertIn("Composite: 52 / 100", out)
        self.assertIn("APPROVED WITH CONDITIONS", out)

    def test_failing_check_contradicts_the_record(self):
        self.add_criterion("4.3", check="4.3.sh")
        self.add_record("4.3", FRESH_DATE, self.first_sha, 2)
        self.write("standard/checks/4.3.sh", "#!/usr/bin/env bash\necho 'CHECK 4.3 a FAIL broken'\nexit 1\n")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "0", out)
        self.assertEqual(rows["4.3"]["state"], "contradicted", out)
        self.assertEqual(code, 1, out)
        self.write("standard/checks/4.3.sh", "#!/usr/bin/env bash\necho 'CHECK 4.3 a PASS fine'\nexit 0\n")
        code, rows, out = self.run_scorer()
        self.assertEqual(rows["4.3"]["current"], "2", out)
        self.assertEqual(code, 0, out)

    def test_failing_check_without_a_record_is_not_a_violation(self):
        self.add_criterion("4.2", check="4.2.sh")
        self.write("standard/checks/4.2.sh", "#!/usr/bin/env bash\necho 'CHECK 4.2 b FAIL unbacked=3'\nexit 1\n")
        code, rows, out = self.run_scorer()
        self.assertEqual(code, 0, out)
        self.assertEqual(rows["4.2"]["state"], "none")
        self.assertTrue(rows["4.2"]["check"].startswith("fail"), out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
