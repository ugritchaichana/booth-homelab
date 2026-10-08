# Decisions

The full list is the [ADR index](../adr/README.md); the one-row-per-decision log (D1 to D86, with options and the deciding criterion) is section 6 of [requirements.md](../platform/requirements.md). This page groups the records by area and gives the reason in one line, so a reader can see which choices were forced by the reference machine and which were taste. A "forced" choice should be re-examined when porting ([porting.md](porting.md)).

## Governance and records

| ADR | Why |
|---|---|
| [ADR 0001](../adr/0001-record-architecture-decisions.md) | Reasoning is kept beside the code so a later team can tell forced choices from taste |
| [ADR 0002](../adr/0002-keep-the-repository-neutral-and-english-only.md) | A neutral, English-only repository is the baseline an adopter forks |
| [ADR 0034](../adr/0034-publish-the-requirements-as-a-redacted-copy-of-the-operators-document.md) | The requirements are published as a redacted copy because the repository is public |
| [ADR 0052](../adr/0052-publish-sanitized-evidence-and-knowledge-in-the-repository.md) | Results live in the repository as sanitized, hash-indexed copies; exact-value substitution because a pattern mask once rewrote a package version |
| [ADR 0053](../adr/0053-prove-phase-4-on-a-runner-template-clone-before-runners-exist.md) | Phase 4 was proven on a runner-template clone because the real runners would bypass the Phase 5 entry gates |

## Host and hypervisor (reference machine; mostly forced)

| ADR | Why |
|---|---|
| [ADR 0003](../adr/0003-host-proxmox-ve-as-a-nested-hyper-v-guest-on-the-workstation.md) | The workstation already runs a hypervisor under VBS and nested KVM was measured to work |
| [ADR 0004](../adr/0004-install-proxmox-ve-9-1-unattended-from-a-prepared-iso.md) | The 9.2 installer fails on Hyper-V Gen2; an answer file makes the install repeatable |
| [ADR 0005](../adr/0005-use-the-no-subscription-repository-and-upgrade-through-ansible.md) | No paid repository; upgrades are code, proven by `changed=0` on the second run |
| [ADR 0006](../adr/0006-isolate-the-vm-behind-an-internal-switch-and-winnat.md) | The only uplink is Wi-Fi, so an external switch is out; an internal switch plus NAT with a fixed range |
| [ADR 0007](../adr/0007-enforce-a-host-side-isolation-layer-with-hyper-v-port-acls.md) | A switch-enforced layer outside the VM, because the VM carries untrusted-code guests on a host with private routes |
| [ADR 0008](../adr/0008-keep-proxmox-off-the-tailnet-and-reach-the-ui-through-the-host.md) | A guest has no mesh-VPN route to leak into if PVE is not on that network |
| [ADR 0014](../adr/0014-run-host-setup-in-one-elevated-pass-that-never-reboots-with-the-owner-in-hyper-v-administrators.md) | One elevated pass that never reboots keeps the owner's prompts to a minimum |
| [ADR 0019](../adr/0019-take-restore-points-of-the-pve-vm-only-while-it-is-off.md) | A running nested VM cannot be checkpointed safely; Off-only checkpoints restore in about 16 s |
| [ADR 0028](../adr/0028-block-the-hyper-v-socket-transport-in-the-pve-guest.md) | `hv_sock` is a host-guest channel outside every network control |
| [ADR 0035](../adr/0035-leave-the-storage-definitions-as-the-installer-made-them-in-phase-2.md) | Changing storage definitions needs a privilege that also deletes any volume, so storage stays as installed |

## Operator toolchain, access and secrets

| ADR | Why |
|---|---|
| [ADR 0009](../adr/0009-store-secrets-with-sops-and-age-in-the-repository.md) | SOPS plus age moves with one key to any host; losing the key loses every secret |
| [ADR 0010](../adr/0010-run-the-operator-toolchain-in-wsl-with-pinned-verified-binaries.md) | Ansible and the install-ISO tool are Linux-only and CI is Linux, so one pinned toolchain |
| [ADR 0011](../adr/0011-reach-proxmox-from-wsl-through-an-ssh-proxycommand-on-the-windows-host.md) | The direct path from WSL to PVE fails; a ProxyCommand through the Windows host works without a new listener |
| [ADR 0022](../adr/0022-render-the-ssh-config-with-the-host-key-pinned-from-sops.md) | The SSH config is rendered with the host key pinned from SOPS, removing first-use trust |
| [ADR 0023](../adr/0023-run-ansible-as-a-key-only-automation-user-and-harden-sshd-behind-a-dead-man.md) | A key-only automation user with a dead-man timer makes a lockout self-healing |
| [ADR 0029](../adr/0029-reach-the-proxmox-api-through-an-ssh-forward-and-skip-tls-verification-inside-it.md) | The API is reached through an SSH forward, so the authenticated channel is the pinned SSH hop and TLS verification inside it is skipped; revisit when the control path moves off the workstation (ADR text, "Rationale and trade-offs") |
| [ADR 0033](../adr/0033-keep-one-sops-file-per-consumer-and-host-with-one-writer-each.md) | One SOPS file per consumer and host, one writer each, avoids lost updates and keeps the root password out of OpenTofu's environment |
| [ADR 0013](../adr/0013-keep-opentofu-state-local-and-encrypted-until-the-cache-service-exists.md) | State stays local and encrypted, one state per stack and host |
| [ADR 0051](../adr/0051-keep-opentofu-state-local-instead-of-moving-it-to-the-cache.md) | State is not moved to the cache because the cache is reachable by untrusted runners and is not an S3 store |

## Infrastructure as code and ownership

| ADR | Why |
|---|---|
| [ADR 0012](../adr/0012-use-opentofu-and-ansible-for-infrastructure-as-code.md) | OpenTofu declares objects, Ansible configures systems; more tools only with a recorded reason |
| [ADR 0017](../adr/0017-size-templates-by-generic-cloud-flavors.md) | Sizes come from a generic cloud-flavor catalog so an adopter maps their own baseline |
| [ADR 0018](../adr/0018-manage-several-machines-as-independent-hosts-in-one-inventory.md) | Independent hosts in one inventory; a cluster is impossible on one machine |
| [ADR 0021](../adr/0021-keep-one-inventory-file-as-the-single-host-data-source.md) | One inventory file makes adding a host a data change |
| [ADR 0025](../adr/0025-keep-one-owner-per-object-and-let-ansible-own-the-proxmox-firewall-files.md) | One owner per object; Ansible owns firewall files so OpenTofu's token stays narrow |
| [ADR 0026](../adr/0026-bootstrap-the-opentofu-api-identity-with-ansible-and-keep-its-token-in-sops.md) | The identity that runs OpenTofu is never managed by OpenTofu |
| [ADR 0024](../adr/0024-test-roles-with-molecule-on-hosted-runners-and-prove-host-changes-locally.md) | Hosted CI cannot reach the lab, so it runs lint and Molecule; host changes are proven locally and pasted into PR bodies |
| [ADR 0020](../adr/0020-retire-the-bootstrap-cache-and-ansible-assets-of-the-previous-host-instead-of-porting-them.md) | The previous host's assets target a retired system or compete with the new firewall, so they are retired, not ported |

## Network and isolation

| ADR | Why |
|---|---|
| [ADR 0027](../adr/0027-use-the-classic-proxmox-firewall-with-a-security-group-for-guest-egress.md) | The classic firewall is supported; the nftables one is a tech preview |
| [ADR 0030](../adr/0030-give-guests-a-routed-source-nated-simple-sdn-zone-with-static-addresses.md) | One declared routed, source-NATed zone with static addresses serves probes and runners |
| [ADR 0031](../adr/0031-prove-guest-isolation-with-a-red-first-run-paired-controls-and-one-run-per-restart-phase.md) | A blocked probe without a control proves nothing, and a check that never ran red proves nothing |
| [ADR 0032](../adr/0032-reach-the-probe-guests-over-ssh-from-the-proxmox-host-with-a-key-that-never-leaves-it.md) | The probe's control channel is SSH from pve01 with a key that never leaves it |
| [ADR 0037](../adr/0037-make-the-guest-firewall-guard-reject-extra-enabled-rules-on-vnet-guests.md) | A permissive extra rule beside the group rule survived the old guard |
| [ADR 0047](../adr/0047-give-the-guest-firewall-guard-a-per-vnet-policy.md) | With a second vnet, a per-vnet policy replaces flags and catches guests on any other bridge |

## Templates

| ADR | Why |
|---|---|
| [ADR 0015](../adr/0015-run-docker-workloads-in-vms-never-in-privileged-containers.md) | Docker for public-repository code runs in VMs, never privileged containers |
| [ADR 0036](../adr/0036-keep-templates-in-their-own-pool-and-let-the-provisioner-token-only-clone-them.md) | A separate pool and a clone-only role mean the provisioner token cannot alter a template |
| [ADR 0038](../adr/0038-build-golden-templates-with-a-root-orchestrator-a-sandboxed-guest-step-and-in-guest-ansible.md) | The host never parses guest output; a root orchestrator, a sandboxed guest step and in-guest Ansible |
| [ADR 0039](../adr/0039-keep-templates-as-proxmox-templates-on-local-lvm-and-check-clone-origins-before-deleting-one.md) | Proxmox templates with linked clones on `local-lvm`; deletion only after the orchestrator's own clone-origin check because LVM-thin does not refuse it |
| [ADR 0040](../adr/0040-version-templates-with-a-monotonic-number-a-root-only-current-tag-and-automatic-promotion.md) | Monotonic versions, a root-only `current` tag and automatic promotion after verification |
| [ADR 0041](../adr/0041-let-the-template-role-own-base-images-snippets-content-and-the-weekly-rebuild.md) | The template role owns base images, snippets and the weekly rebuild because deleting volumes needs a privilege no token holds |
| [ADR 0042](../adr/0042-pin-runner-template-toolchains-by-hash.md) | Toolchains come from release tarballs with pinned hashes; the repository's self-hosted jobs skip tool setup |
| [ADR 0043](../adr/0043-use-debians-docker-io-in-the-vm-class-with-a-socket-only-daemon.md) | Debian's `docker.io` with a unix socket only: no third-party key, distribution security cadence |
| [ADR 0044](../adr/0044-select-golden-templates-fail-closed-and-clone-the-r15-probe-from-them.md) | Consumers resolve templates fail closed among pool members; clones inherit tags, so the pool is the boundary |

## Build cache

| ADR | Why |
|---|---|
| [ADR 0045](../adr/0045-place-the-cache-on-its-own-routed-vnet.md) | The guest vnet isolates ports and the hypervisor must not serve untrusted runners, so a container on its own routed vnet |
| [ADR 0046](../adr/0046-open-one-group-level-path-from-runners-to-the-cache.md) | One group-level rule keeps the guard's allowed set small |
| [ADR 0048](../adr/0048-serve-the-build-cache-with-bazel-remote.md) | Only bazel-remote verifies content digests on upload, splits anonymous reads from writes and evicts by size in its own code |
| [ADR 0049](../adr/0049-key-caches-by-content-and-restore-outputs-only-on-an-exact-match.md) | Content keys and exact-match outputs eliminate the stale-binary hypothesis |
| [ADR 0050](../adr/0050-allow-anonymous-cache-reads-and-gate-writes-with-one-writer-credential.md) | Anonymous reads mean a pull-request job holds nothing to leak; one writer credential gates writes; its branch policy is an open owner setting |

## Release close-out

| ADR | Why |
|---|---|
| [ADR 0054](../adr/0054-run-ci-on-hosted-runners-until-the-runner-pool-exists.md) | No runner of the new platform exists, so the old self-hosted default would queue every run for 24 hours; hosted until Phase 5 |
| [ADR 0055](../adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md) | The Proxmox interface has no instance-type field; a guest list plus one command makes a guest of a cloud flavor and records the flavor in its tags |
| [ADR 0056](../adr/0056-keep-one-implementation-of-the-affected-test-selector.md) | The affected-test selector existed twice and had drifted; the shell script is the only one |
| [ADR 0057](../adr/0057-measure-coverage-with-coverage-py-and-pester.md) | Coverage.py and Pester give a measured number per suite with a regression floor; no target is invented |
| [ADR 0058](../adr/0058-keep-proxmox-login-hardening-off-in-the-reference-lab.md) | A learning lab stays easy to use: TOTP on `root@pam` is off, with the conditions and steps to turn it on |

## Decided direction, not built

| ADR | Why |
|---|---|
| [ADR 0016](../adr/0016-scale-ci-with-an-ephemeral-runner-pool-and-overflow-to-hosted-runners.md) | An ephemeral pool with a controller, overflowing to hosted runners, removes the untrusted-execution blocker and keeps the laptop optional |

## Open and close-out decisions

| Decision | State | Input |
|---|---|---|
| D10 controller, build or adopt | Open | Research recommends building, see [next-phases.md](next-phases.md); HYPOTHESIS until the scale-set spike |
| D11 controller language | Open | The same research recommends Go |
| D60 TOTP for `root@pam` and the notification target | TOTP decided off for the lab (D90, ADR 0058); notifications open | Notifications wait for Phase 7 |
| D85 general object storage (artifacts, backups, state) | Handed off to Phase 7 with backups | Candidate: Garage, S3-compatible and maintained; ADR 0048 rejected it only as a cache because it lacks LRU eviction |
| Shared OpenTofu state backend | Not decided | Local state suits one operator (ADR 0013); a team needs a shared, locked, encrypted backend, which D85 storage could provide; ADR 0051 rules out the cache |
| D86 lab machines after the release | Decided: keep every machine running as evidence | Supersedes the on-demand stop of D21 (VM start policy) |
