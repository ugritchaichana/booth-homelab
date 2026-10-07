# Knowledge and evidence

The repository holds the platform's measured results and what was learned building it, not only its code.

| Where | What |
|---|---|
| `docs/evidence/<phase>/` | Sanitized transcripts and reports of runs on the real host, one directory per phase, each with an `INDEX.md` |
| `docs/knowledge/real-host-defects.md` | Every defect only the real host exposed, with its fix and the pull request that carries it |
| `docs/knowledge/test-catalogue.md` | One row per test file: what it proves, the exact local command, the CI job, and where only the host proves it |

## Reading an evidence index

Each `docs/evidence/<phase>/INDEX.md` has one row per published file: the claim the file backs (`proves`), the sha256 of the original, the sha256 of the published copy, and how many values were replaced, counted by label family and never listed. A row that reads `withheld` says why the file is not published; the original's hash is kept so the claim stays traceable.

Hash-anchored files (template manifests whose sha256 is recorded in a template description) are published only when they need no change. A change of one byte would break the anchor, so they are withheld instead.

## Publishing evidence

Role: the operator who holds the raw run output, on the operator workstation. The raw files, the value map and the credential mask stay outside the repository; only the published copies and the index are committed.

```
python3 scripts/evidence/publish.py --repo . \
  --allow-addresses-from iac --allow-addresses-from tests \
  --map <value-map.json> \
  --mask-script <mask-script.py> \
  --deny-list <deny-list.txt> \
  --raw-root plans=<directory holding the raw run folders> \
  --raw-root logs=<directory holding the host transcripts> \
  scripts/evidence/selection-phase1.json \
  scripts/evidence/selection-phase2.json \
  scripts/evidence/selection-phase3.json
```

Run it from the repository root with Python 3.11 or newer on Linux or WSL (the mask script must pass newlines through unchanged). Notes:

- Every `--allow-addresses-from` directory is read through `git ls-files`, so git must be able to read the checkout. From a linked worktree opened in WSL, export `GIT_DIR` and `GIT_WORK_TREE` (the worktree's git directory and its root, in WSL form) first.
- `--deny-list` may be omitted when the list sits at its default location (`homelab/deny-list.txt` under the local application data directory); the run then picks it up on its own.
- `scripts/evidence/allowed-addresses.txt` is read automatically.
- To publish one phase, name only its selection file. The exit code is non-zero if a file is withheld by a checker flag or a credential-mask marker; an anchored file that needs a substitution is recorded as withheld without failing the run.
- A withheld file is never edited by hand. Read its `file:line:rule` output, add the exact value to the map (or a justified line to `allowed-addresses.txt`), and run the same command again.

The selection file lists `{src, dest, proves}` entries; `src` is `<root name>:<path under that root>`, `dest` stays under `docs/evidence/<phase>/`, and `"anchored": true` marks a hash-anchored file. For each entry the tool reads the raw bytes, replaces exact map values (longest first, in one pass), runs the credential mask, checks the result, writes it and refreshes the index. Any checker flag or mask marker withholds that file and the run exits non-zero.

Check what is committed, as CI does:

```
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge \
  --allow-addresses-from iac --allow-addresses-from tests
python3 -m unittest discover -s tests/evidence -v
```

`--check` prints `file:line:rule` and never the matched text. Hard rules fail the run: an IPv4 address outside `10.99.0.0/16` and the explicit allowlist (loopback, `0.0.0.0`, `1.1.1.1`, `1.0.0.1`, the documentation ranges, netmasks, any address already present in a git-tracked file under a directory named by `--allow-addresses-from` except `iac/secrets/`, and any address listed with a reason in `scripts/evidence/allowed-addresses.txt`), a Windows user path, a path segment naming the operator's tooling directory, an email address (a systemd unit name such as `name@instance.service` and a `.arpa` special-use name are not emails), a tailnet domain, a private-key header, an age secret key prefix, a PVE API token with a value, a GitHub token prefix, a Thai character and the credential-mask marker. Version-like tokens (a four-part dotted number glued to a version suffix or prefix, as in a package version) and non-ASCII characters are soft: they are listed for review and do not fail the run.

Operators can add a hard word check that never reaches the repository: `--deny-list <file>` (one word per line, `#` comments; the file lives outside the repository, by default in the local application data directory under `homelab/deny-list.txt`) flags any case-insensitive occurrence as `file:line:deny-list` without printing the word. CI runs without it.

## Why only exact values are replaced

A pattern that rewrites anything shaped like an IPv4 address once rewrote part of a package version string and faked a hash mismatch. The publisher therefore substitutes only values listed in the operator's map, whole-value and longest first; for a value shaped like an address it also refuses to cut it out of a longer dotted number. Anything the map does not list is not rewritten: the checker flags it, the file is withheld, and the operator decides whether to extend the map. Each `INDEX.md` records which address allow sources were used. A published file is never hand-edited.

## Rules for knowledge pages

Neutral English; no operator paths, machine names, user names or real addresses; link evidence by its index, not by a local path.
