# 02. Golden Templates

Runners and services are cloned from templates that are built once, sized by cloud flavor and rebuilt weekly. The runner pool controller (the consumer of the templates) is handed off. Measured build times and probe results: [docs/handoff/results.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/results.md).

## Classes

| Class | Kind | VMID block | Content (pins in `iac/ansible/roles/pve_templates/files/bundles/<class>/versions.yml`) |
|---|---|---|---|
| `lxc-runner` | Unprivileged container, Debian 13 base | 9200 to 9299 | .NET SDK 8 and 10, Node 22, the GitHub Actions runner (installed, never configured), a non-root runner user without sudo; all from release tarballs pinned by hash (ADR 0042) |
| `vm-docker` | VM, Debian 13 cloud image | 9300 to 9399 | Debian's `docker.io` with a socket-only daemon, the Actions runner (installed, never configured) (ADR 0043) |

Docker workloads run only in the VM class (ADR 0015). Sizes come from the flavor catalog `iac/tofu/flavors.json` (ADR 0017). Guests created from a template by flavor: [ADR 0055](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md), `scripts/iac/new-guest.sh`.

## How a build runs

`homelab-template`, a root orchestrator on the host (ADR 0038):

1. Pre-flight: free-space and thin-pool thresholds; a build refuses above them.
2. Creates the guest stopped, reads every network, firewall and shape attribute back, and only then starts it.
3. A non-root, sandboxed guest-facing step (`IPAddressDeny=any`) runs Ansible inside the guest, scans it for secrets, seals it and fetches the manifest.
4. Converts to a template, verifies a linked clone, tags it and promotes it.
5. Retires versions older than `previous`, only after checking that no clone depends on them (ADR 0039).

A failed build destroys its own guest and leaves a failure marker. A systemd timer rebuilds both classes weekly with catch-up (ADR 0041).

## Versions, tags and rollback

| Item | Rule | Decision |
|---|---|---|
| Version | Monotonic `vN` per class | ADR 0040 |
| Pointer | Tag `current`, moved only by root, promoted automatically after verification | ADR 0040 |
| Retention | `current` and `previous` | ADR 0039 |
| Rollback | `homelab-template rollback <class>` swaps the two; a second call swaps back | ADR 0040 |
| Manifest | Hashes to the `manifest_sha256` stored in the template description | [requirements.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/platform/requirements.md) row 56, measured retention and manifest |
| Pool | Templates live in pool `templates`; the provisioner token holds `VM.Clone` and `VM.Audit` there and nothing else | ADR 0036 |

## Consuming a template

A consumer never names a VMID. The OpenTofu module `iac/tofu/modules/proxmox/template-source` returns the one template of a class that carries the marker, the class and the tag `current`, or the version a pin names. The plan stops unless exactly one match exists, it is a template, it belongs to pool `templates` and its VMID is inside the class block (ADR 0044). Linked clones inherit the template's tags and its guest firewall, so stacks do not redeclare a clone's firewall.

## Known gap

cloud-init restores the default user's passwordless sudo at a VM clone's first boot, although the seal removed it. Tracked in [docs/handoff/limits-and-gaps.md](https://github.com/ugritchaichana/booth-homelab/blob/master/docs/handoff/limits-and-gaps.md) as a gate for the runner pool controller.

Procedures: [RUNBOOK.md](https://github.com/ugritchaichana/booth-homelab/blob/master/RUNBOOK.md), "Day-2 operations", "Golden templates".
