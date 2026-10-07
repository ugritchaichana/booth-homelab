#!/usr/bin/env python3
"""Publish operator-local evidence into docs/evidence with exact-value sanitizing, and check published text."""

from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import os
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

LAB_NET = ipaddress.ip_network("10.99.0.0/16")
ALLOWED_ADDRESSES = frozenset(
    ipaddress.ip_address(a) for a in ("127.0.0.1", "0.0.0.0", "1.1.1.1", "1.0.0.1")
)
# Loopback and the three documentation ranges carry no operator data.
ALLOWED_NETWORKS = tuple(
    ipaddress.ip_network(n)
    for n in ("10.99.0.0/16", "127.0.0.0/8", "192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")
)

DOTTED = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+){3,}(?![0-9])")
VERSION_PREV = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-+~")
VERSION_NEXT = frozenset("-+~abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

LINE_RULES: dict[str, re.Pattern[str]] = {
    "windows-user-path": re.compile(r"(?i)[a-z]:[\\/]+users[\\/]|/mnt/[a-z]/users/"),
    "email": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"),
    "operator-path": re.compile(r"(?i)(?<![A-Za-z0-9._-])\.claude(?![A-Za-z0-9._-])"),
    "tailnet-domain": re.compile(r"(?i)\.ts\.net(?![A-Za-z0-9-])"),
    "private-key-header": re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"),
    "age-secret-key": re.compile("AGE-SECRET-" + "KEY-"),
    "pve-api-token": re.compile(r"PVEAPIToken=[^\s=]+=(?![<${])[^\s\"']{8,}"),
    "github-token": re.compile(r"(?<![A-Za-z0-9])(?:ghp_|gho_|ghs_|ghu_|ghr_|github_pat_)"),
    "thai-char": re.compile("[\u0e00-\u0e7f]"),
    "masked-marker": re.compile(re.escape("<MASKED:")),
}
SOFT_RULES = ("version-like", "non-ascii")
UNIT_TYPES = frozenset(
    ("service", "socket", "timer", "target", "mount", "automount", "path", "slice", "scope", "device", "swap")
)
SECRETS_PREFIX = "iac/secrets/"
NON_ASCII = re.compile(r"[^\x00-\x7f]")


@dataclass(frozen=True)
class Finding:
    line: int
    rule: str
    soft: bool = False


def _is_netmask(value: int) -> bool:
    inverted = ~value & 0xFFFFFFFF
    return inverted & (inverted + 1) == 0


def _address_allowed(address: ipaddress.IPv4Address, known: frozenset[ipaddress.IPv4Address]) -> bool:
    return (
        address in ALLOWED_ADDRESSES
        or address in known
        or any(address in net for net in ALLOWED_NETWORKS)
        or _is_netmask(int(address))
    )


def _version_like(line: str, start: int, end: int) -> bool:
    prev = line[start - 1] if start > 0 else ""
    nxt = line[end] if end < len(line) else ""
    if prev in VERSION_PREV or nxt in VERSION_NEXT:
        return True
    return prev == ":" and start > 1 and line[start - 2].isdigit()


def _quad_address(token: str) -> ipaddress.IPv4Address | None:
    parts = token.split(".")
    if len(parts) == 4 and all(p == str(int(p)) and int(p) <= 255 for p in parts):
        return ipaddress.IPv4Address(token)
    return None


def _rule_hits(rule: str, pattern: re.Pattern[str], line: str) -> bool:
    if rule != "email":
        return pattern.search(line) is not None
    for match in pattern.finditer(line):
        domain = match.group().split("@", 1)[1].lower()
        last = domain.rsplit(".", 1)[-1]
        if last not in UNIT_TYPES and last != "arpa":
            return True
    return False


def tracked_addresses(repo: Path, dirs: list[str]) -> frozenset[ipaddress.IPv4Address]:
    found: set[ipaddress.IPv4Address] = set()
    for directory in dirs:
        listing = subprocess.run(
            ["git", "-C", str(repo), "ls-files", "-z", "--", directory], capture_output=True, check=True
        ).stdout
        for name in filter(None, listing.decode("utf-8").split(chr(0))):
            if name.startswith(SECRETS_PREFIX):
                continue
            path = repo / name
            if not path.is_file():
                continue
            text = path.read_bytes().decode("utf-8", errors="replace")
            found.update(a for m in DOTTED.finditer(text) if (a := _quad_address(m.group())) is not None)
    return frozenset(found)


def load_allowed_addresses(path: Path) -> frozenset[ipaddress.IPv4Address]:
    allowed: set[ipaddress.IPv4Address] = set()
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"(\S+)\s+#\s*(\S.*)", line)
        if match is None:
            raise ValueError(f"{path.name}:{number}: each address needs ' # <reason>'")
        try:
            allowed.add(ipaddress.IPv4Address(match.group(1)))
        except ValueError:
            raise ValueError(f"{path.name}:{number}: not an IPv4 address") from None
    return frozenset(allowed)


def load_deny_list(path: Path) -> tuple[str, ...]:
    words = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        word = raw.strip()
        if word and not word.startswith("#"):
            words.append(word.lower())
    return tuple(words)


def default_deny_list() -> Path | None:
    candidates = []
    if os.environ.get("LOCALAPPDATA"):
        candidates.append(Path(os.environ["LOCALAPPDATA"]) / "homelab" / "deny-list.txt")
    candidates.extend(sorted(Path("/mnt/c/Users").glob("*/AppData/Local/homelab/deny-list.txt")))
    return next((c for c in candidates if c.is_file()), None)


def scan_text(
    text: str, known: frozenset[ipaddress.IPv4Address] = frozenset(), deny: tuple[str, ...] = ()
) -> list[Finding]:
    findings: list[Finding] = []
    for number, line in enumerate(text.splitlines(), start=1):
        for rule, pattern in LINE_RULES.items():
            if _rule_hits(rule, pattern, line):
                findings.append(Finding(number, rule))
        if deny and any(word in line.lower() for word in deny):
            findings.append(Finding(number, "deny-list"))
        if NON_ASCII.search(line) and not LINE_RULES["thai-char"].search(line):
            findings.append(Finding(number, "non-ascii", soft=True))
        for match in DOTTED.finditer(line):
            address = _quad_address(match.group())
            if address is not None and _address_allowed(address, known):
                continue
            if address is None or _version_like(line, match.start(), match.end()):
                findings.append(Finding(number, "version-like", soft=True))
            else:
                findings.append(Finding(number, "ipv4-outside-lab"))
    return findings


def check_paths(
    paths: list[Path], known: frozenset[ipaddress.IPv4Address] = frozenset(), deny: tuple[str, ...] = ()
) -> tuple[list[tuple[Path, Finding]], int]:
    results: list[tuple[Path, Finding]] = []
    files = 0
    for root in paths:
        candidates = sorted(p for p in root.rglob("*") if p.is_file()) if root.is_dir() else [root]
        for path in candidates:
            files += 1
            text = path.read_bytes().decode("utf-8", errors="replace")
            results.extend((path, f) for f in scan_text(text, known, deny))
    return results, files


def run_check(
    paths: list[Path], known: frozenset[ipaddress.IPv4Address] = frozenset(), deny: tuple[str, ...] = ()
) -> int:
    results, files = check_paths(paths, known, deny)
    for path, finding in results:
        if finding.rule == "non-ascii":
            continue
        print(f"{path.as_posix()}:{finding.line}:{finding.rule}")
    hard = Counter(f.rule for _, f in results if not f.soft)
    soft = Counter(f.rule for _, f in results if f.soft)
    print(
        f"checked {files} files: hard={dict(sorted(hard.items()))} soft={dict(sorted(soft.items()))}",
        file=sys.stderr,
    )
    return 1 if hard else 0


def family(label: str) -> str:
    match = re.fullmatch(r"<(.+?)(?:-\d+)?(?:-(?:addr|name))?>", label)
    return match.group(1) if match else label


def _is_ipv4_shaped(value: str) -> bool:
    return re.fullmatch(r"[0-9]+(?:\.[0-9]+){3}", value) is not None


class Substituter:
    def __init__(self, pairs: list[tuple[str, str]]) -> None:
        ordered = sorted(
            {value: label for value, label in pairs if value}.items(), key=lambda kv: (-len(kv[0]), kv[0])
        )
        self._labels = dict(ordered)
        parts = []
        for value, _ in ordered:
            escaped = re.escape(value)
            if _is_ipv4_shaped(value):
                escaped = rf"(?<![0-9])(?<![0-9]\.){escaped}(?![0-9])(?!\.[0-9])"
            parts.append(escaped)
        self._pattern = re.compile("|".join(parts)) if parts else None

    def apply(self, text: str) -> tuple[str, Counter[str]]:
        counts: Counter[str] = Counter()
        if self._pattern is None:
            return text, counts

        def replace(match: re.Match[str]) -> str:
            label = self._labels[match.group()]
            counts[family(label)] += 1
            return label

        return self._pattern.sub(replace, text), counts


def load_map(path: Path) -> list[tuple[str, str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    return [(str(value), str(label)) for value, label in data["pairs"]]


def run_mask(data: bytes, script: Path) -> bytes:
    proc = subprocess.run(
        [sys.executable, str(script)], input=data, capture_output=True, check=True
    )
    return proc.stdout


def decode_text(raw: bytes) -> str:
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    return raw.decode("utf-8-sig")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@dataclass
class Entry:
    src: str
    dest: str
    proves: str
    anchored: bool = False


@dataclass
class Outcome:
    entry: Entry
    raw_sha: str
    published_sha: str | None = None
    substitutions: Counter[str] = field(default_factory=Counter)
    withheld: str | None = None
    fatal: bool = False
    flags: list[Finding] = field(default_factory=list)


def resolve_source(src: str, roots: dict[str, Path]) -> Path:
    name, sep, rel = src.partition(":")
    if not sep or name not in roots:
        raise SystemExit(f"src {src!r} needs a known raw root prefix ({', '.join(sorted(roots))})")
    if ".." in Path(rel).parts:
        raise SystemExit(f"src {src!r} must not contain '..'")
    return roots[name] / rel


def process_entry(
    entry: Entry,
    roots: dict[str, Path],
    subst: Substituter,
    mask_script: Path,
    repo: Path,
    phase: str,
    known: frozenset[ipaddress.IPv4Address] = frozenset(),
    deny: tuple[str, ...] = (),
) -> Outcome:
    dest_dir = (repo / "docs" / "evidence" / phase).resolve()
    dest = (repo / entry.dest).resolve()
    if dest_dir not in dest.parents:
        raise SystemExit(f"dest {entry.dest!r} is outside docs/evidence/{phase}")
    raw = resolve_source(entry.src, roots).read_bytes()
    outcome = Outcome(entry, sha256(raw))
    text, counts = subst.apply(decode_text(raw))
    outcome.substitutions = counts
    masked = run_mask(text.encode("utf-8"), mask_script)
    published_text = masked.decode("utf-8")
    mask_changed = masked != text.encode("utf-8")
    if b"<MASKED:" in masked:
        outcome.withheld = "withheld: credential mask matched"
        outcome.fatal = True
    else:
        outcome.flags = [f for f in scan_text(published_text, known, deny) if not f.soft]
        needed = sum(counts.values()) + (1 if mask_changed else 0)
        if entry.anchored and needed:
            outcome.withheld = f"withheld: needs {needed} substitutions"
        elif outcome.flags:
            rules = Counter(f.rule for f in outcome.flags)
            outcome.withheld = f"withheld: {len(outcome.flags)} checker flags ({', '.join(sorted(rules))})"
            outcome.fatal = True
    if outcome.withheld is None:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(masked)
        outcome.published_sha = sha256(masked)
    elif dest.exists():
        dest.unlink()
    return outcome


def render_index(phase: str, outcomes: list[Outcome], sources: list[str] | None = None) -> str:
    lines = [
        f"# Evidence index: {phase}",
        "",
        "Generated by `scripts/evidence/publish.py`; do not edit by hand.",
        "",
        "Address allow sources: " + (", ".join(f"`{s}`" for s in sources) if sources else "none") + ".",
        "",
        "| file | proves | raw sha256 | published sha256 | substitutions by label family |",
        "|---|---|---|---|---|",
    ]
    for o in sorted(outcomes, key=lambda x: x.entry.dest):
        name = Path(o.entry.dest).name
        if o.withheld:
            published, subs = o.withheld, "-"
        else:
            published = f"`{o.published_sha}`"
            subs = ", ".join(f"{k}: {v}" for k, v in sorted(o.substitutions.items())) or "0"
        file_cell = name if o.withheld else f"[{name}]({name})"
        lines.append(f"| {file_cell} | {o.entry.proves} | `{o.raw_sha}` | {published} | {subs} |")
    return "\n".join(lines) + "\n"


DEFAULT_ALLOWED_FILE = Path(__file__).with_name("allowed-addresses.txt")


def collect_known(args: argparse.Namespace, repo: Path) -> tuple[frozenset[ipaddress.IPv4Address], list[str]]:
    known: set[ipaddress.IPv4Address] = set()
    sources: list[str] = []
    if args.allow_addresses_from:
        known |= tracked_addresses(repo, args.allow_addresses_from)
        sources += [f"git-tracked addresses under {d}/" for d in args.allow_addresses_from]
    allowed_file = Path(args.allowed_addresses_file) if args.allowed_addresses_file else DEFAULT_ALLOWED_FILE
    if allowed_file.exists():
        try:
            known |= load_allowed_addresses(allowed_file)
        except ValueError as error:
            raise SystemExit(str(error)) from None
        sources.append(allowed_file.name)
    return frozenset(known), sources


def collect_deny(args: argparse.Namespace) -> tuple[str, ...]:
    path = Path(args.deny_list) if args.deny_list else default_deny_list()
    return load_deny_list(path) if path else ()


def run_publish(args: argparse.Namespace) -> int:
    repo = Path(args.repo).resolve()
    roots: dict[str, Path] = {}
    for spec in args.raw_root:
        name, sep, path = spec.partition("=")
        if not sep:
            raise SystemExit(f"--raw-root needs name=path, got {spec!r}")
        roots[name] = Path(path)
    subst = Substituter(load_map(Path(args.map)))
    known, sources = collect_known(args, repo)
    deny = collect_deny(args)
    status = 0
    for selection_path in args.selection:
        selection = json.loads(Path(selection_path).read_text(encoding="utf-8"))
        phase = selection["phase"]
        entries = [Entry(**e) for e in selection["entries"]]
        outcomes = [
            process_entry(e, roots, subst, Path(args.mask_script), repo, phase, known, deny) for e in entries
        ]
        index = repo / "docs" / "evidence" / phase / "INDEX.md"
        index.parent.mkdir(parents=True, exist_ok=True)
        index.write_text(render_index(phase, outcomes, sources), encoding="utf-8", newline="\n")
        totals: Counter[str] = Counter()
        for o in outcomes:
            totals.update(o.substitutions)
            for f in o.flags:
                print(f"{o.entry.dest}:{f.line}:{f.rule}")
            if o.withheld:
                print(f"{o.entry.dest}: {o.withheld}", file=sys.stderr)
            status |= 1 if o.fatal else 0
        published = sum(1 for o in outcomes if not o.withheld)
        print(
            f"{phase}: published={published} withheld={len(outcomes) - published} "
            f"substitutions={dict(sorted(totals.items()))}",
            file=sys.stderr,
        )
    return status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", nargs="+", metavar="PATH", help="scan published text and exit non-zero on a flag")
    parser.add_argument("--map", help="evidence value map (JSON with a pairs list)")
    parser.add_argument("--mask-script", help="stdin-to-stdout credential mask script")
    parser.add_argument(
        "--raw-root", action="append", default=[], metavar="NAME=PATH", help="operator-local root a src prefix NAME: resolves under"
    )
    parser.add_argument("--repo", default=".", help="repository root (default: current directory)")
    parser.add_argument(
        "--allow-addresses-from",
        action="append",
        default=[],
        metavar="DIR",
        help="IPv4 addresses in git-tracked files under DIR (never iac/secrets) are not flagged",
    )
    parser.add_argument(
        "--deny-list",
        metavar="FILE",
        help="operator-side word list (one per line, # comments) whose case-insensitive occurrence is a hard flag; "
        "default: homelab/deny-list.txt under the local app data directory when it exists",
    )
    parser.add_argument(
        "--allowed-addresses-file",
        metavar="FILE",
        help="address list with a required reason per line (default: allowed-addresses.txt next to this script)",
    )
    parser.add_argument("selection", nargs="*", help="selection JSON files to publish")
    args = parser.parse_args(argv)
    if args.check:
        known, _ = collect_known(args, Path(args.repo).resolve())
        return run_check([Path(p) for p in args.check], known, collect_deny(args))
    if not (args.selection and args.map and args.mask_script and args.raw_root):
        parser.error("publishing needs selection files, --map, --mask-script and --raw-root")
    return run_publish(args)


if __name__ == "__main__":
    sys.exit(main())
