# 02. Golden Templates

Runners and services are cloned from templates that are built once, sized by cloud flavor and rebuilt on a schedule. No runner is cloned from them yet: the runner pool controller is Phase 5 and is handed off.

## Classes

| Class | Kind | VMID block | Content (pins in `iac/ansible/roles/pve_templates/files/bundles/<class>/versions.yml`) |
|---|---|---|---|
| `lxc-runner` | Unprivileged container, Debian 13 base | 9200 to 9299 | .NET SDK 8 and 10, Node 22, the GitHub Actions runner (installed, never configured), a non-root runner user without sudo; all from release tarballs pinned by hash (ADR 0042) |
| `vm-docker` | VM, Debian 13 cloud image | 9300 to 9399 | Debian's `docker.io` with a socket-only daemon, the Actions runner (installed, never configured) (ADR 0043) |

Docker workloads run only in the VM class (ADR 0015). Sizes come from the flavor catalog `iac/tofu/flavors.json` (ADR 0017); `aws/t3.medium` plans 2 cores, 4096 MB and 30 GB (row 60).

## How a build runs

A root orchestrator on the host (`homelab-template`, ADR 0038):

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
| Manifest | Hashes to the `manifest_sha256` stored in the template description | row 56 |
| Pool | Templates live in pool `templates`; the provisioner token holds `VM.Clone` and `VM.Audit` there and nothing else | ADR 0036 |

## Consuming a template

A consumer never names a VMID. The OpenTofu module `iac/tofu/modules/proxmox/template-source` returns the one template of a class that carries the marker, the class and the tag `current`, or the version a pin names. The plan stops unless exactly one match exists, it is a template, it belongs to pool `templates` and its VMID is inside the class block (ADR 0044). Linked clones inherit the template's tags and its guest firewall, so stacks do not redeclare a clone's firewall (row 58).

## Measured

| Result | Row |
|---|---|
| Both classes build on `pve01`: about 2 min 15 s (`lxc-runner`), about 3 min 5 s (`vm-docker`) | 55; [build log](../docs/evidence/phase3/build-weekly-3.txt), [timer-fired builds](../docs/evidence/phase3/journal-timer-fired.txt) |
| After six builds each class holds exactly two versions; the weekly timer fired; rollback exit 0 on both classes | 56 |
| The provisioner token gets 403 on deleting or retagging a template and 200 on cloning it | 57 |
| R15 on clones of both templates: 15/15 negatives blocked, 1/1 positive; the VM clone runs `docker run hello-world`, exposes no `svm`/`vmx`, has no Docker TCP listener | 59 |

## Known gap

cloud-init restores the default user's passwordless sudo at a VM clone's first boot, although the seal removed it. It is a Phase 5 entry gate (row 59; `docs/knowledge/real-host-defects.md`).

Procedures: `RUNBOOK.md` sections 9 and 10.
