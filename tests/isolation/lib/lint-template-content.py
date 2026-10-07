#!/usr/bin/env python3
"""Lint every golden-template content bundle under files/bundles/<class>/ for unpinned or unauthenticated installs."""
import os
import re
import sys

import yaml

HEX = {"sha256": 64, "sha512": 128}
VERSION = re.compile(r"^\d+\.\d+(\.\d+){0,2}$")
LINE_RULES = [
    ("pipe to a shell", re.compile(r"\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:/\S*/)?(?:ba|da|z|k|a)?sh\b")),
    ("shell fed by a download", re.compile(r"\b(?:ba)?sh\s+-c\s+[\"']?\$\(\s*(?:curl|wget)|<\(\s*(?:curl|wget)")),
    ("[trusted=yes] apt source", re.compile(r"trusted\s*=\s*yes", re.I)),
    ("unauthenticated apt install", re.compile(r"--allow-unauthenticated|AllowUnauthenticated", re.I)),
    ("the word latest", re.compile(r"\blatest\b", re.I)),
]
APT_SOURCE = re.compile(r"^\s*deb(?:-src)?\s|apt_repository|sources\.list\.d")
FINGERPRINT = re.compile(r"\b[0-9A-Fa-f]{40}\b")


def text_lines(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return handle.read().splitlines()
    except (UnicodeDecodeError, OSError):
        return None


def lint_versions(path, findings):
    try:
        with open(path, encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except FileNotFoundError:
        findings.append("%s: versions.yml is missing" % path)
        return
    artifacts = (data or {}).get("artifacts")
    if not isinstance(artifacts, dict) or not artifacts:
        findings.append("%s: no artifacts are pinned" % path)
        return
    for name, entry in artifacts.items():
        entry = entry if isinstance(entry, dict) else {}
        if not VERSION.match(str(entry.get("version", ""))):
            findings.append("%s: artifact %s has no exact version" % (path, name))
        if not str(entry.get("url", "")).startswith("https://"):
            findings.append("%s: artifact %s has no https url" % (path, name))
        hashes = [k for k in HEX if k in entry]
        if len(hashes) != 1 or not re.fullmatch(r"[0-9a-f]{%d}" % HEX[hashes[0]], str(entry[hashes[0]])):
            findings.append("%s: artifact %s has no valid sha256 or sha512 pin" % (path, name))
    for source in (data or {}).get("apt_sources") or []:
        if not source.get("signed_by") or not FINGERPRINT.fullmatch(str(source.get("key_fingerprint", "")).replace(" ", "")):
            findings.append("%s: apt source %s needs signed_by and a 40-hex key_fingerprint" % (path, source.get("name", "?")))


def lint_file(path, findings):
    lines = text_lines(path)
    if lines is None:
        return
    source_lines = []
    for number, line in enumerate(lines, 1):
        if line.lstrip().startswith("#"):
            continue
        for label, rule in LINE_RULES:
            if rule.search(line):
                findings.append("%s:%d: %s" % (path, number, label))
        if APT_SOURCE.search(line):
            source_lines.append(number)
            if re.match(r"^\s*deb(?:-src)?\s", line) and "signed-by=" not in line:
                findings.append("%s:%d: apt source without signed-by=" % (path, number))
    if source_lines and not any(FINGERPRINT.search(line) for line in lines):
        findings.append("%s:%d: apt source without a pinned key fingerprint in the same file" % (path, source_lines[0]))
    block, start = [], 1
    for number, line in enumerate(lines + ["    - name: end"], 1):
        if re.match(r"^\s*- name:", line):
            if any("get_url" in b for b in block) and not any("checksum:" in b for b in block):
                findings.append("%s:%d: get_url task without checksum:" % (path, start))
            block, start = [], number
        block.append(line)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "..", "iac", "ansible", "roles", "pve_templates", "files", "bundles")
    findings, classes = [], 0
    for cls in sorted(os.listdir(root)):
        folder = os.path.join(root, cls)
        if not os.path.isdir(folder):
            continue
        classes += 1
        lint_versions(os.path.join(folder, "versions.yml"), findings)
        for current, _, names in os.walk(folder):
            for name in sorted(names):
                lint_file(os.path.join(current, name), findings)
    if classes == 0:
        findings.append("%s: no class bundle found" % root)
    for finding in findings:
        print("FINDING " + finding)
    if findings:
        return 1
    print("OK: %d class bundle(s) pass the pinning and provenance rules" % classes)
    return 0


sys.exit(main())
