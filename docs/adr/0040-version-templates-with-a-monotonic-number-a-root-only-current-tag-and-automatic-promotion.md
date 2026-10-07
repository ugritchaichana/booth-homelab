# 0040. Version templates with a monotonic number, a root-only current tag and automatic promotion

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D68 in docs/platform/requirements.md

## Context

ADR 0017 requires every template to carry a version tag and a manifest, and a rollback to be one switch. Consumers (the OpenTofu runner stack now, the pool controller in Phase 5) must pick a template without trusting anything a runner or the provisioner token can change. ADR 0036 already removed delete and retag from every token by putting templates in their own pool; moving the pointer stays a root action.

Questions to settle: how versions are numbered and where they live, what the pointer is, when a new version becomes current, what a consumer may rely on, and what rollback does.

## Options considered

1. A repository variable as the pointer, promoted by a reviewed change — the toolchain diff is seen in a pull request, but every weekly build waits for a merge that needs an approving reviewer.
2. A `current` tag set by root, promoted automatically after verification — no human step, so the unreviewed delta is whatever the operating system's own updates bring in.
3. Both a tag and a repository pin with no precedence — the looser of the two becomes the real policy.

## Decision

Option 2, with a pin that may override the tag.

- Version numbers are a monotonic integer `N` per class, kept in the root state and written before the guest is created, so a failed build burns its number and a deleted version never frees one. When the state file is absent the counter starts above the highest `v<N>` tag found in the class block.
- Names: `tmpl-<class>-v<N>` for a template and `build-<class>-v<N>` for a guest still being built. Classes: `lxc-runner` and `vm-docker`.
- VMID blocks, one per class, clear of the probe guests 9101 and 9102: `lxc-runner` 9200-9299 and `vm-docker` 9300-9399. In a block, `base + 1` is the verification clone and `base + 2` to `base + 99` hold versions, allocated lowest free, so a build guest becomes the template under its own VMID and `qm create` refusing an existing VMID is the collision guard. The role asserts that blocks are distinct, divisible by 100 and free of reserved VMIDs.
- Tags, set after create and never at create: the marker `homelab-template`, the class, `v<N>`, and `current` on exactly one version per class. Only root writes them.
- `current` moves only after the new version passed verification (ADR 0039), automatically. The orchestrator writes the new `current` and the old one as `previous` into its root state first, then the tags (the old `current` is stripped first). Between the two tag writes no version carries `current`, and consumers fail closed in that window. `homelab-template repair <class>` rewrites the tags from the recorded state if a crash left them apart, and `status` reports the difference.
- At each promotion the manifest diff against the version being replaced goes to the journal (printed by the sandboxed step, ADR 0038), together with one root line naming the old and new version, the VMID and the manifest sha256.
- Rollback is one root command, `homelab-template rollback <class>`: it swaps `current` and `previous` in the state, then the tags, and journals it. The next build promotes on top of the rolled-back version, so the version rolled back from is the one retention retires (ADR 0039).
- Consumers resolve through the API by tags and fail closed unless exactly one guest matches the marker, the class and `current`, and that guest is a template, sits in the templates pool and has a VMID inside the class block. `homelab-template status [class]` applies the same rule to the host's own view and exits non-zero unless every class has exactly one current, so the check a consumer will make is runnable by hand.
- A consumer pin overrides the tag when set: the precedence is the pin if present, else the tag. A pin must pass the same checks except the `current` tag (template, pool, block, marker, class, and a `v<N>` tag equal to the pinned number).
- The template description carries host-chosen values only (class, version, build date, manifest sha256), never a manifest field.

## Rationale and trade-offs

- Pins are already reviewed in pull requests and the verification step compares what was built with what was asked for. What nobody reviews in the automatic path is the operating-system updates inside a weekly rebuild. The journaled diff and the one-command rollback are the compensating signal; the diff is read, not enforced.
- The manifest is reported by the guest, so it is a record, not an attestation. It catches drift and mistakes, not a signed but malicious upstream.
- A tag is a weaker pointer than a repository variable because anything holding `VM.Config.Options` on the template could move it; the templates pool leaves that privilege with root alone (ADR 0036). Consumers add the template, pool and VMID-block checks so a tag on a running guest cannot be selected.
- Accepted: during the two tag writes a consumer sees zero current templates and refuses. That is a short availability gap, preferred to two currents.
- The consumer-side resolution (zero matches, two matches, a tag on a non-template) is a separate change with its own tests; this ADR defines the contract it implements.
- `tests/isolation/test-template-build.sh` pins promotion, rollback, the one-current rule in `status`, and the state-versus-tag mismatch.
