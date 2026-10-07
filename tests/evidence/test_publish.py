import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCRIPT_DIR = Path(os.environ.get("EVIDENCE_PUBLISH_DIR", HERE.parents[1] / "scripts" / "evidence"))

spec = importlib.util.spec_from_file_location("publish", SCRIPT_DIR / "publish.py")
publish = importlib.util.module_from_spec(spec)
sys.modules["publish"] = publish
spec.loader.exec_module(publish)

LEAK_IP = "8.8.4.4"
PRIVATE_LEAK_IP = "172.16.5.4"


def rules_of(text: str, soft: bool = False) -> set[tuple[int, str]]:
    return {(f.line, f.rule) for f in publish.scan_text(text) if f.soft == soft}


class SubstituterTests(unittest.TestCase):
    def test_longest_value_wins_at_the_same_position(self):
        sub = publish.Substituter([("alpha", "<short-1>"), ("alpha-beta", "<long-1>")])
        text, counts = sub.apply("x alpha-beta y alpha z")
        self.assertEqual(text, "x <long-1> y <short-1> z")
        self.assertEqual(counts, {"long": 1, "short": 1})

    def test_substituted_label_is_never_rewritten_again(self):
        sub = publish.Substituter([("secret-host", "<node-1>"), ("node", "<other-1>")])
        text, _ = sub.apply("secret-host and node")
        self.assertEqual(text, "<node-1> and <other-1>")

    def test_address_value_is_not_cut_out_of_a_longer_address_or_version(self):
        sub = publish.Substituter([(PRIVATE_LEAK_IP, "<host-route-1-addr>")])
        for untouched in (f"{PRIVATE_LEAK_IP[:-1]}40", f"5.{PRIVATE_LEAK_IP}", f"{PRIVATE_LEAK_IP}.9"):
            self.assertEqual(sub.apply(f"seen {untouched} here")[0], f"seen {untouched} here")
        self.assertEqual(sub.apply(f"to {PRIVATE_LEAK_IP}.")[0], "to <host-route-1-addr>.")

    def test_version_string_without_a_map_value_is_not_rewritten(self):
        sub = publish.Substituter([(PRIVATE_LEAK_IP, "<host-route-1-addr>")])
        line = "Setting up libfoo (1.2.3.4-1) and v1.2.3.4"
        self.assertEqual(sub.apply(line)[0], line)
        self.assertEqual(rules_of(line), set())
        self.assertEqual(rules_of(line, soft=True), {(1, "version-like")})

    def test_family_strips_index_and_suffix(self):
        self.assertEqual(publish.family("<host-route-10-addr>"), "host-route")
        self.assertEqual(publish.family("<workstation-addr-3>"), "workstation-addr")
        self.assertEqual(publish.family("<tailnet-node-0-name>"), "tailnet-node")
        self.assertEqual(publish.family("<user-home>"), "user-home")


class CheckerRules(unittest.TestCase):
    def assertFlags(self, line: str, rule: str) -> None:
        self.assertIn((1, rule), rules_of(line), f"{rule} did not fire")

    def assertClean(self, line: str) -> None:
        self.assertEqual(rules_of(line), set(), line)

    def test_ipv4_outside_lab(self):
        self.assertFlags(f"peer {LEAK_IP}:22", "ipv4-outside-lab")
        self.assertFlags(f"peer {PRIVATE_LEAK_IP}", "ipv4-outside-lab")
        self.assertFlags(f"addr:{LEAK_IP}", "ipv4-outside-lab")

    def test_ipv4_allowlist(self):
        for ok in ("10.99.0.2", "10.99.16.22:22", "127.0.0.1", "0.0.0.0", "1.1.1.1", "1.0.0.1", "203.0.113.7",
                   "198.51.100.9", "192.0.2.1", "255.255.255.0"):
            self.assertClean(f"host {ok} up")

    def test_windows_user_path(self):
        self.assertFlags("C:" + "\\Users\\someone\\x", "windows-user-path")
        self.assertFlags("/mnt/c/" + "Users/someone/x", "windows-user-path")
        self.assertFlags("c:/" + "users/someone", "windows-user-path")

    def test_email(self):
        self.assertFlags("mail someone@example.org now", "email")
        self.assertFlags("mail alice@example.org now", "email")
        self.assertFlags("mail ops@corp.example.net now", "email")

    def test_systemd_unit_names_are_not_emails(self):
        for unit in ("service", "socket", "timer", "target", "mount", "automount", "path", "slice", "scope", "device", "swap"):
            self.assertClean(f"unit homelab-template-build@lxc-runner.{unit} failed")

    def test_arpa_special_use_names_are_not_emails(self):
        self.assertClean("ssh root@pve01.home.arpa now")
        self.assertFlags("ssh root@pve01.home.arpa.example.org now", "email")

    def test_ipv6_global(self):
        for line in ("peer 2606:4700:4700::1112 up", "to [2a00:1450:4001:81b::200e]:443", "addr 2001:4860:4860:0:0:0:0:8888"):
            self.assertFlags(line, "ipv6-global")
        for line in ("link fe80::1009:71ff:feba:d8a1%eth0:22", "ula fd00::1 and fc00::2", "doc 2001:db8::1", "doc 3fff::1",
                     "loop ::1 and ::", "resolver 2606:4700:4700::1111 and 2606:4700:4700::1001", "at 08:04:39 today", "mac aa:bb:cc:dd:ee:ff", "mapped ::ffff:10.99.0.2", "multicast ff02::1"):
            self.assertEqual({r for _, r in rules_of(line)} - {"ipv4-outside-lab"}, set(), line)

    def test_ci_writer_credential(self):
        self.assertFlags("auth ci-writer:" + "hunter2hunter2", "ci-writer-credential")
        for line in ("auth ci-writer:<password>", "auth ci-writer:${PASSWORD}", "auth ci-writer:$PASSWORD",
                     "user ci-writer: a service account", "key 'ci-writer:'", "ci-writer:"):
            self.assertClean(line)

    def test_bcrypt_hash(self):
        self.assertFlags("htpasswd line ci-writer:$2" + "y$05$" + "a" * 20, "bcrypt-hash")
        self.assertFlags("$2" + "b$12$x", "bcrypt-hash")
        self.assertClean("price is $20 and $2 only")

    def test_operator_path(self):
        for line in ("see ~/.claude/plans/x", "/home/u/.CLAUDE/notes", "C:/tools/.claude", "dir .claude here"):
            self.assertFlags(line, "operator-path")
        for line in ("a file named x.claude.txt", "claude is a name", "my.claude"):
            self.assertClean(line)

    def test_tailnet_domain(self):
        self.assertFlags("node1.tail1234." + "ts.net", "tailnet-domain")

    def test_private_key_header(self):
        self.assertFlags("-----BEGIN " + "OPENSSH PRIVATE KEY-----", "private-key-header")

    def test_age_secret_key(self):
        self.assertFlags("AGE-SECRET-" + "KEY-1" + "Q" * 10, "age-secret-key")

    def test_pve_api_token_value_only(self):
        self.assertFlags("Authorization: PVEAPIToken=tofu@pve!provisioner=" + "0123abcd-4567-89ef", "pve-api-token")
        self.assertNotIn((1, "pve-api-token"), rules_of("PVEAPIToken=tofu@pve!provisioner=<secret>"))

    def test_github_token_prefix(self):
        self.assertFlags("token " + "ghp_" + "x" * 36, "github-token")
        self.assertFlags("token " + "github_pat_" + "x" * 30, "github-token")

    def test_thai_character(self):
        self.assertFlags("note \u0e2a\u0e27\u0e31\u0e2a\u0e14\u0e35", "thai-char")

    def test_masked_marker(self):
        self.assertFlags("value <MASKED:" + "name>", "masked-marker")

    def test_version_like_is_soft_only(self):
        for line in ("pkg 1.2.3.4-1", "pkg v1.2.3.4", "pkg 1:1.2.3.4-1", "pkg 1.2.3.4+dfsg", "pkg 1.2.3.4~rc1", "pkg 1.2.3.4a",
                     "pkg 1.2.3.4.5"):
            self.assertEqual(rules_of(line), set(), line)
            self.assertEqual(rules_of(line, soft=True), {(1, "version-like")}, line)

    def test_non_ascii_other_than_thai_is_soft(self):
        self.assertEqual(rules_of("box \u2502 line", soft=True), {(1, "non-ascii")})
        self.assertEqual(rules_of("box \u2502 line"), set())

    def test_every_rule_is_covered_by_a_test(self):
        tested = {n[5:] for n in dir(self) if n.startswith("test_")}
        for rule in publish.LINE_RULES:
            self.assertTrue(any(rule.replace("-", "_") in t for t in tested), rule)


class CheckModeTests(unittest.TestCase):
    def run_check(self, directory: Path) -> tuple[int, str]:
        out = StringIO()
        with redirect_stdout(out), redirect_stderr(StringIO()):
            code = publish.main(["--check", str(directory)])
        return code, out.getvalue()

    def test_leak_fails_and_output_never_contains_the_matched_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.txt").write_text(f"fine\nleak {LEAK_IP} here\n", encoding="utf-8")
            code, out = self.run_check(Path(tmp))
        self.assertEqual(code, 1)
        self.assertEqual(out.strip().rsplit(":", 2)[1:], ["2", "ipv4-outside-lab"])
        self.assertNotIn(LEAK_IP, out)

    def test_soft_only_passes_and_is_listed(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.txt").write_text("pkg 1.2.3.4-1\n", encoding="utf-8")
            code, out = self.run_check(Path(tmp))
        self.assertEqual(code, 0)
        self.assertTrue(out.strip().endswith(":1:version-like"))

    def test_clean_directory_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "a.txt").write_text("lab 10.99.0.2 ok\n", encoding="utf-8")
            self.assertEqual(self.run_check(Path(tmp))[0], 0)


class PublishTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.repo = self.root / "repo"
        self.raw = self.root / "raw"
        self.repo.mkdir()
        self.raw.mkdir()
        self.map = self.root / "map.json"
        self.map.write_text(json.dumps({"pairs": [[PRIVATE_LEAK_IP, "<host-route-1-addr>"], ["real-box", "<tailnet-node-0>"]]}))
        self.mask = self.root / "mask.py"
        self.mask.write_text("import sys\nsys.stdout.buffer.write(sys.stdin.buffer.read())\n")

    def publish(self, entries: list[dict], mask: Path | None = None) -> tuple[int, str]:
        selection = self.root / "selection.json"
        selection.write_text(json.dumps({"phase": "p", "entries": entries}))
        with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            code = publish.main(
                ["--repo", str(self.repo), "--map", str(self.map), "--mask-script", str(mask or self.mask),
                 "--raw-root", f"plans={self.raw}", str(selection)]
            )
        return code, (self.repo / "docs/evidence/p/INDEX.md").read_text(encoding="utf-8")

    def entry(self, name: str, content: bytes, **extra) -> dict:
        (self.raw / name).write_bytes(content)
        return {"src": f"plans:{name}", "dest": f"docs/evidence/p/{name}", "proves": "a claim", **extra}

    def test_index_hashes_match_the_bytes_and_substitutions_are_counted(self):
        raw = f"ssh real-box via {PRIVATE_LEAK_IP}\nlab 10.99.0.2\n".encode()
        code, index = self.publish([self.entry("a.txt", raw)])
        published = (self.repo / "docs/evidence/p/a.txt").read_bytes()
        self.assertEqual(code, 0)
        self.assertEqual(published, b"ssh <tailnet-node-0> via <host-route-1-addr>\nlab 10.99.0.2\n")
        self.assertIn(f"`{hashlib.sha256(raw).hexdigest()}`", index)
        self.assertIn(f"`{hashlib.sha256(published).hexdigest()}`", index)
        self.assertIn("host-route: 1, tailnet-node: 1", index)
        self.assertNotIn(PRIVATE_LEAK_IP, index)
        self.assertNotIn("real-box", index)

    def test_anchored_file_needing_a_substitution_is_withheld(self):
        raw = f'{{"addr": "{PRIVATE_LEAK_IP}"}}\n'.encode()
        code, index = self.publish([self.entry("m.json", raw, anchored=True)])
        self.assertEqual(code, 0)
        self.assertFalse((self.repo / "docs/evidence/p/m.json").exists())
        self.assertIn("withheld: needs 1 substitutions", index)
        self.assertIn(hashlib.sha256(raw).hexdigest(), index)

    def test_anchored_file_needing_nothing_is_published_byte_for_byte(self):
        raw = b'{"version": "1.2.3.4-1"}\n'
        code, index = self.publish([self.entry("m.json", raw, anchored=True)])
        self.assertEqual(code, 0)
        self.assertEqual((self.repo / "docs/evidence/p/m.json").read_bytes(), raw)
        self.assertIn(f"`{hashlib.sha256(raw).hexdigest()}` | `{hashlib.sha256(raw).hexdigest()}` | 0", index)

    def test_checker_flag_withholds_the_file_and_fails_the_run(self):
        code, index = self.publish([self.entry("bad.txt", f"leak {LEAK_IP}\n".encode())])
        self.assertEqual(code, 1)
        self.assertFalse((self.repo / "docs/evidence/p/bad.txt").exists())
        self.assertIn("withheld: 1 checker flags (ipv4-outside-lab)", index)

    def test_masked_marker_stops_publishing_the_file(self):
        marker = self.root / "marking-mask.py"
        marker.write_text("import sys\nsys.stdin.buffer.read()\nsys.stdout.write('<MASKED:' + 'name>')\n")
        code, index = self.publish([self.entry("a.txt", b"plain\n")], mask=marker)
        self.assertEqual(code, 1)
        self.assertFalse((self.repo / "docs/evidence/p/a.txt").exists())
        self.assertIn("withheld: credential mask matched", index)

    def test_utf16_source_is_published_as_utf8(self):
        code, _ = self.publish([self.entry("t.txt", "line one\r\n".encode("utf-16"))])
        self.assertEqual(code, 0)
        self.assertEqual((self.repo / "docs/evidence/p/t.txt").read_bytes(), b"line one\r\n")

    def test_index_records_the_allow_sources_used(self):
        git_repo(self.repo, {"iac/d.yml": f"probe: {LEAK_IP}\n"})
        allowed = self.root / "allowed.txt"
        allowed.write_text("9.9.9.9 # a vector\n", encoding="utf-8")
        entry = self.entry("a.txt", f"peer {LEAK_IP} and 9.9.9.9\n".encode())
        selection = self.root / "selection.json"
        selection.write_text(json.dumps({"phase": "p", "entries": [entry]}))
        with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            code = publish.main(
                ["--repo", str(self.repo), "--map", str(self.map), "--mask-script", str(self.mask),
                 "--raw-root", f"plans={self.raw}", "--allow-addresses-from", "iac",
                 "--allowed-addresses-file", str(allowed), str(selection)]
            )
        index = (self.repo / "docs/evidence/p/INDEX.md").read_text(encoding="utf-8")
        self.assertEqual(code, 0)
        self.assertIn("Address allow sources: `git-tracked addresses under iac/`, `allowed.txt`.", index)

    def test_dest_outside_the_phase_directory_is_refused(self):
        entry = self.entry("a.txt", b"x\n")
        entry["dest"] = "docs/evidence/other/a.txt"
        with self.assertRaises(SystemExit):
            self.publish([entry])


def git_repo(root: Path, files: dict[str, str], untracked: dict[str, str] | None = None) -> Path:
    root.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    subprocess.run(["git", "-C", str(root), "init", "-q"], check=True, env=env)
    for name, text in {**files, **(untracked or {})}.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    subprocess.run(["git", "-C", str(root), "add", "--", *files], check=True, env=env)
    return root


class TrackedAddressTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = git_repo(
            Path(self._tmp.name, "repo"),
            {
                "iac/role/defaults.yml": f"probe: {LEAK_IP}\n",
                "tests/vectors.sh": "vec 9.9.9.9\n",
                "iac/secrets/key.yml": f"host: {PRIVATE_LEAK_IP}\n",
                "tests/evidence/test_vectors.py": "leak = '5.5.5.5'\n",
            },
            untracked={"iac/role/local.yml": "x: 4.4.4.4\n"},
        )

    def known(self, *dirs: str):
        return publish.tracked_addresses(self.repo, list(dirs))

    def test_address_in_a_tracked_file_is_allowed(self):
        known = self.known("iac", "tests")
        self.assertEqual({str(a) for a in known}, {LEAK_IP, "9.9.9.9"})
        self.assertEqual(publish.scan_text(f"peer {LEAK_IP}", known), [])

    def test_address_absent_from_tracked_files_still_flags(self):
        known = self.known("iac", "tests")
        self.assertEqual(rules_of("peer 4.4.4.4", soft=False), {(1, "ipv4-outside-lab")})
        self.assertEqual({(f.line, f.rule) for f in publish.scan_text("peer 4.4.4.4", known)}, {(1, "ipv4-outside-lab")})

    def test_address_only_under_iac_secrets_still_flags(self):
        known = self.known("iac")
        self.assertNotIn(publish.ipaddress.ip_address(PRIVATE_LEAK_IP), known)
        self.assertEqual({(f.line, f.rule) for f in publish.scan_text(f"peer {PRIVATE_LEAK_IP}", known)}, {(1, "ipv4-outside-lab")})

    def test_the_checkers_own_test_directory_is_never_a_source(self):
        known = self.known("tests", "tests/evidence")
        self.assertNotIn(publish.ipaddress.ip_address("5.5.5.5"), known)
        self.assertEqual({(f.line, f.rule) for f in publish.scan_text("peer 5.5.5.5", known)}, {(1, "ipv4-outside-lab")})

    def test_only_the_named_directories_are_read(self):
        self.assertEqual({str(a) for a in self.known("tests")}, {"9.9.9.9"})

    def test_check_mode_uses_the_allow_option(self):
        target = Path(self._tmp.name, "published")
        target.mkdir()
        (target / "a.txt").write_text(f"peer {LEAK_IP}\n", encoding="utf-8")
        for extra, expected in (([], 1), (["--allow-addresses-from", "iac"], 0)):
            with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
                code = publish.main(["--check", str(target), "--repo", str(self.repo), "--allowed-addresses-file",
                                     str(Path(self._tmp.name, "none.txt")), *extra])
            self.assertEqual(code, expected, extra)


class AllowedAddressFileTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.path = Path(self._tmp.name, "allowed.txt")

    def test_a_listed_address_is_allowed(self):
        self.path.write_text(f"# header\n\n{LEAK_IP} # range boundary vector\n", encoding="utf-8")
        known = publish.load_allowed_addresses(self.path)
        self.assertEqual(publish.scan_text(f"peer {LEAK_IP}", known), [])
        self.assertEqual({(f.line, f.rule) for f in publish.scan_text(f"peer {PRIVATE_LEAK_IP}", known)},
                         {(1, "ipv4-outside-lab")})

    def test_a_line_without_a_reason_fails_to_load(self):
        for line in (LEAK_IP, f"{LEAK_IP} #", f"{LEAK_IP} # "):
            self.path.write_text(line + "\n", encoding="utf-8")
            with self.assertRaises(ValueError, msg=line):
                publish.load_allowed_addresses(self.path)

    def test_a_line_that_is_not_an_address_fails_to_load(self):
        self.path.write_text("not-an-address # reason\n", encoding="utf-8")
        with self.assertRaises(ValueError):
            publish.load_allowed_addresses(self.path)

    def test_the_committed_list_loads_and_every_entry_has_a_reason(self):
        self.assertTrue(publish.load_allowed_addresses(SCRIPT_DIR / "allowed-addresses.txt"))


class DenyListTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.list = self.root / "deny.txt"
        self.list.write_text("# comment\n\nExampleCorp\n", encoding="utf-8")
        self.target = self.root / "published"
        self.target.mkdir()

    def test_word_is_a_hard_flag_in_any_case_without_being_reported(self):
        deny = publish.load_deny_list(self.list)
        for line in ("grep examplecorp here", "grep EXAMPLECORP here", "see ExampleCorp-internal"):
            self.assertEqual({(f.line, f.rule) for f in publish.scan_text(line, deny=deny)}, {(1, "deny-list")}, line)
        self.assertEqual(publish.scan_text("grep another word", deny=deny), [])

    def test_comments_and_blank_lines_are_not_words(self):
        self.assertEqual(publish.load_deny_list(self.list), ("examplecorp",))

    def test_check_mode_prints_file_line_rule_only_and_fails(self):
        (self.target / "a.txt").write_text("fine\nowned by examplecorp\n", encoding="utf-8")
        out = StringIO()
        with redirect_stdout(out), redirect_stderr(StringIO()):
            code = publish.main(["--check", str(self.target), "--deny-list", str(self.list)])
        self.assertEqual(code, 1)
        self.assertTrue(out.getvalue().strip().endswith("a.txt:2:deny-list"))
        self.assertNotIn("examplecorp", out.getvalue().lower())

    def test_without_a_list_nothing_is_denied(self):
        (self.target / "a.txt").write_text("owned by examplecorp\n", encoding="utf-8")
        with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            self.assertEqual(publish.run_check([self.target]), 0)


class MutationTests(unittest.TestCase):
    NEW_BEHAVIOURS = (
        ("unit and arpa names exempt from email",
         "def _rule_hits(rule, pattern, line):\n    return pattern.search(line) is not None\n",
         "test_publish.CheckerRules.test_systemd_unit_names_are_not_emails"),
        ("arpa names exempt from email",
         "def _rule_hits(rule, pattern, line):\n    return pattern.search(line) is not None\n",
         "test_publish.CheckerRules.test_arpa_special_use_names_are_not_emails"),
        ("tracked addresses allowed",
         "def tracked_addresses(repo, dirs):\n    return frozenset()\n",
         "test_publish.TrackedAddressTests.test_address_in_a_tracked_file_is_allowed"),
        ("iac/secrets excluded",
         'EXCLUDED_PREFIXES = ("iac/nothing-is-secret/",)\n',
         "test_publish.TrackedAddressTests.test_address_only_under_iac_secrets_still_flags"),
        ("tests/evidence excluded as a source",
         'EXCLUDED_PREFIXES = ("iac/secrets/",)\n',
         "test_publish.TrackedAddressTests.test_the_checkers_own_test_directory_is_never_a_source"),
        ("global IPv6 rule",
         "def _global_ipv6(token):\n    return False\n",
         "test_publish.CheckerRules.test_ipv6_global"),
        ("ci-writer credential rule",
         'LINE_RULES["ci-writer-credential"] = re.compile(r"(?!x)x")\n',
         "test_publish.CheckerRules.test_ci_writer_credential"),
        ("bcrypt rule",
         'LINE_RULES["bcrypt-hash"] = re.compile(r"(?!x)x")\n',
         "test_publish.CheckerRules.test_bcrypt_hash"),
        ("allowed list requires a reason",
         "def load_allowed_addresses(path):\n"
         "    return frozenset(ipaddress.IPv4Address(l.split()[0]) for l in path.read_text().splitlines()"
         " if l.strip() and not l.startswith('#'))\n",
         "test_publish.AllowedAddressFileTests.test_a_line_without_a_reason_fails_to_load"),
        ("operator-path rule",
         'LINE_RULES["operator-path"] = re.compile(r"(?!x)x")\n',
         "test_publish.CheckerRules.test_operator_path"),
        ("deny list is a hard flag",
         "def load_deny_list(path):\n    return ()\n",
         "test_publish.DenyListTests.test_word_is_a_hard_flag_in_any_case_without_being_reported"),
        ("allowed list is honoured",
         "def load_allowed_addresses(path):\n    return frozenset()\n",
         "test_publish.AllowedAddressFileTests.test_a_listed_address_is_allowed"),
    )

    def test_each_new_behaviour_has_a_test_that_goes_red_without_it(self):
        for name, code, test_id in self.NEW_BEHAVIOURS:
            with self.subTest(name), tempfile.TemporaryDirectory() as tmp:
                Path(tmp, "publish.py").write_text(
                    (SCRIPT_DIR / "publish.py").read_text(encoding="utf-8") + "\n" + code, encoding="utf-8"
                )
                result = subprocess.run(
                    [sys.executable, "-m", "unittest", test_id],
                    cwd=HERE,
                    env={**os.environ, "EVIDENCE_PUBLISH_DIR": tmp},
                    capture_output=True,
                    text=True,
                )
                self.assertNotEqual(result.returncode, 0, name)

    def test_disabling_a_checker_rule_turns_its_test_red(self):
        with tempfile.TemporaryDirectory() as tmp:
            mutant = Path(tmp, "publish.py")
            mutant.write_text(
                (SCRIPT_DIR / "publish.py").read_text(encoding="utf-8")
                + '\nLINE_RULES["email"] = re.compile(r"(?!x)x")\n',
                encoding="utf-8",
            )
            result = subprocess.run(
                [sys.executable, "-m", "unittest", "test_publish.CheckerRules.test_email"],
                cwd=HERE,
                env={**os.environ, "EVIDENCE_PUBLISH_DIR": tmp},
                capture_output=True,
                text=True,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("email did not fire", result.stderr)


if __name__ == "__main__":
    unittest.main()
