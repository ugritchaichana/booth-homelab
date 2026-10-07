# Knowledge and evidence

The repository holds the platform's measured results and what was learned building it, not only its code.

| Where | What |
|---|---|
| `docs/evidence/<phase>/` | Sanitized transcripts and reports of runs on the real host, one directory per phase, each with an `INDEX.md` |
| [`real-host-defects.md`](real-host-defects.md) | Every defect only the real host exposed, with its fix, the pull request and the evidence |
| [`test-catalogue.md`](test-catalogue.md) | What every test proves (happy, bad, edge), its command, its CI job and where only the host proves it |
| [`coverage.md`](coverage.md) | Coverage numbers per suite, with their runs |
| [`previous-agent-debt.md`](previous-agent-debt.md) | Pointer to the items the previous agent left that are still open |

## Reading an evidence index

Each `docs/evidence/<phase>/INDEX.md` has one row per published file: the claim the file backs (`proves`), the sha256 of the original, the sha256 of the published copy, and how many values were replaced, counted by label family and never listed. A row that reads `withheld` says why the file is not published; the original's hash is kept so the claim stays traceable. Hash-anchored files (template manifests whose sha256 is recorded in a template description) are published only when they need no change, because one changed byte breaks the anchor.

## Publishing evidence

Role: the operator who holds the raw run output, on the operator workstation, from the repository root, with Python 3.11 or newer on Linux or WSL. The raw files, the value map, the mask script and the deny list stay outside the repository; only the published copies and the index are committed.

```sh
python3 scripts/evidence/publish.py --repo . \
  --allow-addresses-from iac \
  --map <value-map.json> \
  --mask-script <mask-script.py> \
  --deny-list <deny-list.txt> \
  --raw-root plans=<directory holding the raw run folders> \
  --raw-root logs=<directory holding the host transcripts> \
  scripts/evidence/selection-phase1.json \
  scripts/evidence/selection-phase2.json \
  scripts/evidence/selection-phase3.json \
  scripts/evidence/selection-phase4.json \
  scripts/evidence/selection-closeout.json
```

Name one selection file to publish one phase. The exit code is non-zero when a checker flag or a credential-mask marker withholds a file; an anchored file that needs a substitution is recorded as withheld without failing the run. A withheld file is never edited by hand: read its `file:line:rule` output, add the exact value to the map (or a justified line to `scripts/evidence/allowed-addresses.txt`), and run the same command again.

Notes:

- Every `--allow-addresses-from` directory is read through `git ls-files`, so git must be able to read the checkout. From a linked worktree opened in WSL, export `GIT_DIR` and `GIT_WORK_TREE` (the worktree's git directory and its root, in WSL form) first.
- `--deny-list` may be omitted when the list sits at `homelab/deny-list.txt` under the local application data directory.
- The mask script is the operator's credential mask: stdin to stdout, newlines unchanged. A change it makes counts as one substitution, and a mask marker left in its output (the `masked-marker` rule) withholds the file.

The three inputs, by example:

| Input | Format | Sample |
|---|---|---|
| Value map (`--map`) | JSON with a `pairs` list of `[value, label]`; the real value is replaced whole, longest first, in one pass | `{"pairs": [["192.0.2.10", "<LAN-HOST-1-addr>"], ["operator-name", "<USER-1-name>"]]}` |
| Selection entry | `src` is `<root name>:<path under that root>`, `dest` stays under `docs/evidence/<phase>/`, `"anchored": true` marks a hash-anchored file | `{"src": "plans:run-1/apply.txt", "dest": "docs/evidence/closeout/guest-apply-lxc.txt", "proves": "First apply creates container 9501"}` |
| Checker output (a flag) | `<file>:<line>:<rule>`, never the matched text | `docs/evidence/closeout/guest-apply-lxc.txt:12:ipv4-outside-lab` |

Check what is committed, as CI does:

```sh
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac
python3 -m unittest discover -s tests/evidence -v
```

## Checker rules

A hard rule fails the run; a soft rule is listed for review. `--check` prints `file:line:rule`.

| Rule | Flags |
|---|---|
| `ipv4-outside-lab` | An IPv4 address outside `10.99.0.0/16`, loopback, `0.0.0.0`, `1.1.1.1`, `1.0.0.1`, the documentation ranges, netmasks, any address already in a git-tracked file under an `--allow-addresses-from` directory (never `iac/secrets/` or `tests/evidence/`) and any address listed with a reason in `allowed-addresses.txt` |
| `ipv6-global` | A global unicast IPv6 address other than the documentation ranges and the two public resolvers |
| `windows-user-path` | A Windows or WSL user-profile path |
| `operator-path` | A path segment naming the operator's tooling directory |
| `email` | An email address; a systemd unit name such as `name@instance.service` and a `.arpa` name are not emails |
| `tailnet-domain` | A mesh-VPN domain |
| `private-key-header`, `age-secret-key` | A private-key header, an age secret key prefix |
| `pve-api-token`, `github-token` | A PVE API token with a value, a GitHub token prefix |
| `ci-writer-credential`, `bcrypt-hash` | The cache writer account followed by a non-placeholder value, a bcrypt hash prefix |
| `thai-char` | A Thai character |
| `masked-marker` | The credential-mask marker |
| `deny-list` | A word of the operator's deny list; the word is never printed. CI runs without the list |
| `version-like` (soft) | A dotted number glued to a version suffix or prefix, as in a package version |
| `non-ascii` (soft) | A non-ASCII character |

## Why only exact values are replaced

A pattern that rewrites anything shaped like an IPv4 address once rewrote part of a package version string and faked a hash mismatch. The publisher therefore substitutes only values listed in the operator's map, whole-value and longest first; for a value shaped like an address it also refuses to cut it out of a longer dotted number. Anything the map does not list is not rewritten: the checker flags it, the file is withheld, and the operator decides whether to extend the map. Each `INDEX.md` records which address allow sources were used.

## Rules for knowledge pages

Neutral English; no operator paths, machine names, user names or real addresses; link evidence by its index, not by a local path.
