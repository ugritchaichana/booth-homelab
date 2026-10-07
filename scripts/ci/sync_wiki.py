#!/usr/bin/env python3
"""
Sync local wiki documentation to GitHub Wiki repository.
Target Wiki: https://github.com/ugritchaichana/booth-homelab/wiki
Wiki Git Remote: https://github.com/ugritchaichana/booth-homelab.wiki.git
"""
import glob
import os
import shutil
import subprocess
import sys
import tempfile

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

REPO_NAME = os.environ.get("GITHUB_REPOSITORY", "ugritchaichana/booth-homelab")
TOKEN = os.environ.get("GITHUB_TOKEN")

if TOKEN:
    REPO_WIKI_URL = f"https://x-access-token:{TOKEN}@github.com/{REPO_NAME}.wiki.git"
else:
    REPO_WIKI_URL = f"https://github.com/{REPO_NAME}.wiki.git"

BOT_NAME = "github-actions[bot]"
BOT_EMAIL = "41898283+github-actions[bot]@users.noreply.github.com"

WIKI_SOURCE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "wiki"))

def redact(text):
    return text.replace(TOKEN, "***") if TOKEN else text

def check_wiki_remote():
    """Check if GitHub Wiki Git repository has been initialized."""
    result = subprocess.run(
        ["git", "ls-remote", REPO_WIKI_URL],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    return result.returncode == 0

def sync_wiki():
    if not os.path.exists(WIKI_SOURCE_DIR):
        print(f"[ERROR] Source wiki directory not found at: {WIKI_SOURCE_DIR}")
        sys.exit(1)

    print(f"[*] Checking GitHub Wiki remote availability for {REPO_NAME}")
    if not check_wiki_remote():
        print("[!] GitHub Wiki repository has not been initialized yet.")
        print("[!] Note: GitHub creates the wiki.git repository ONLY after the first page is created in the web UI.")
        print("[!] Action required:")
        print("    1. Open https://github.com/ugritchaichana/booth-homelab/wiki in your browser.")
        print("    2. Click 'Create the first page' and save it (default 'Home' title is fine).")
        print("    3. Re-run this script to automatically publish all documentation pages.")
        sys.exit(2)

    with tempfile.TemporaryDirectory() as temp_dir:
        print(f"[*] Cloning wiki repo to temporary directory: {temp_dir}")
        clone_res = subprocess.run(
            ["git", "clone", REPO_WIKI_URL, temp_dir],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        if clone_res.returncode != 0:
            print(f"[ERROR] Failed to clone wiki: {redact(clone_res.stderr)}")
            sys.exit(1)

        # Copy all files from wiki/ into cloned repository
        wiki_files = glob.glob(os.path.join(WIKI_SOURCE_DIR, "*.md"))
        print(f"[*] Copying {len(wiki_files)} markdown documents from {WIKI_SOURCE_DIR}...")
        for src_file in wiki_files:
            dst_file = os.path.join(temp_dir, os.path.basename(src_file))
            shutil.copy2(src_file, dst_file)
            print(f"    -> Copied: {os.path.basename(src_file)}")

        # Configure local git identity
        subprocess.run(["git", "-C", temp_dir, "config", "user.name", BOT_NAME], check=True)
        subprocess.run(["git", "-C", temp_dir, "config", "user.email", BOT_EMAIL], check=True)

        # Stage and check diff
        subprocess.run(["git", "-C", temp_dir, "add", "."], check=True)
        diff_res = subprocess.run(["git", "-C", temp_dir, "status", "--porcelain"], capture_output=True, text=True)
        
        if not diff_res.stdout.strip():
            print("[✓] Wiki is already up-to-date. No changes to push.")
            return

        # Commit and push
        print("[*] Committing and pushing documentation to GitHub Wiki...")
        commit_res = subprocess.run(
            ["git", "-C", temp_dir, "commit", "-m", "docs(wiki): update knowledge base and system runbooks"],
            capture_output=True,
            text=True
        )
        print(commit_res.stdout.strip())

        branch_res = subprocess.run(
            ["git", "-C", temp_dir, "symbolic-ref", "--short", "HEAD"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        branch = branch_res.stdout.strip()
        if branch_res.returncode != 0 or not branch:
            print("[ERROR] Could not read the wiki default branch from the clone.")
            sys.exit(1)

        push_res = subprocess.run(
            ["git", "-C", temp_dir, "push", "origin", branch],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        if push_res.returncode == 0:
            print("[✓] Successfully synchronized all wiki pages to https://github.com/ugritchaichana/booth-homelab/wiki")
        else:
            print(f"[ERROR] Failed to push to wiki: {redact(push_res.stderr)}")
            sys.exit(1)

if __name__ == "__main__":
    sync_wiki()
