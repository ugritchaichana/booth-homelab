# Defects only the real host exposed

Phases 2 and 3 were built against fakes, disposable containers and offline tests, then run once on the real Proxmox host. Each defect below was found only by that run. The "Fix PR" column is the pull request whose branch carries the fix. Evidence for the runs themselves is indexed in [phase 2](../evidence/phase2/INDEX.md) and [phase 3](../evidence/phase3/INDEX.md); the defect tests that now guard each fix are in [test-catalogue.md](test-catalogue.md).

## Phase 2: host baseline, firewall, API identity, state, guest network, probe

| Defect | Fix | Fix PR |
|---|---|---|
| The first converge failed closed on a missing secret directory for the new API token, and the rescue removed the freshly created token | The `pve_api_identity` role creates the directory before the token bootstrap | #67 |
| The firewall compile check read `ignore <chain> (<hash>)` lines, which Proxmox prints for unchanged chains, as errors. The false positive fired the firewall dead-man on the real host, which restored the previous state (`restore finished rc=0`) | The check patterns now come from the warn and die messages of the installed `Firewall.pm` | #67 |
| Creating a probe VM returned 403 while reading the new disk's volume info: the provisioner token lacked `Datastore.Audit` on the disk storage | `Datastore.Audit` granted on the disk storage | #67 |
| The IPv6 assertion expected forwarding 0 on the guest bridge interface, but per-interface forwarding is host and router behaviour | The assertion reads `all` and `default` forwarding 0 plus the bridge's `accept_ra` and `autoconf` 0 | #67 |
| The second `apply` of the host stack failed with `unsafe characters in the Windows local application data path` while copying the encrypted state: the allowed character set had no backslash, and the copy only runs once a state exists | `scripts/iac/tofu.sh` converts the path with `wslpath` before validating it; quotes, semicolons, dollar signs, backticks and percent signs are still refused | #68 |
| Creating a probe container or VM with tags returned 403: Proxmox checks the tag permission on the guest path without the pool, so a pool-scoped token cannot set tags at create | The probe stack declares no tags and the token was not widened | #71 |
| A volume delete needs `Datastore.Allocate` on the storage, which would also let the token delete any volume there and read the storage config | Not granted; the probe teardown needs one operator `pvesm free` per downloaded file (recorded as a known limitation) | #71 |
| Stopped-VM checkpoint helper: the immediate read of the new checkpoint listed it zero times and the action reported a false FAIL | The action uses `-Passthru` and polls by checkpoint Id | #61 |

## Phase 3: golden templates

| Defect | Fix | Fix PR |
|---|---|---|
| The orchestrator called a `pvesm` subcommand that does not exist on the host (`unknown command`, rc 255) | The local storage content is read through `pvesh get /storage/<id>` | #84 |
| A converge that deployed `versions.yml` and then failed on a later task lost the build trigger: the rerun saw no change and started no build | A root-only pending-build marker under the state directory survives until the build starts | #84 |
| The guest-facing user could not reach the template work directory because its parent was mode 0700 and owned by root | The work directory moved to its own path and the role asserts at converge time that every parent is traversable by other users | #79 |
| Failure cleanup trusted the cluster listing, which lags a just-started guest by seconds, so it skipped the stop and the destroy failed with `container is running` | The stop reads the guest's own `status/current` and cleanup hard-stops before destroying; the fake can now lag its listing | #79 |
| The verify guest unit failed with exit status 226/NAMESPACE because a sandbox mount named a build directory that had been removed | The read-write path entries are optional | #79 |
| The VM build failed on an apt lock held by cloud-init's first-boot `apt-get` | `run.sh` waits for cloud-init before apt | #79 |
| The in-guest secret scan refused the build on the runner's bundled npm config and on npm docs that name a placeholder private key (vm-docker and lxc-runner) | The classes drop the bundled npm docs and the empty `.npmrc`; the three config-definition files are allowlisted by sha256 and path | #80, #82 |
| Linked clones inherit the template's tags, so a probe guest tagged `current` became a second match and broke plan and destroy | Templates resolve only among members of the `templates` pool and the probe clones overwrite the inherited tags | #83 |
| A VM clone's cloud-init drive returned 403 for the guest role | `VM.Config.CDROM` added to the guest role | #83 |
| Linked clones inherit the template's guest firewall, so declaring rules for the VM aborted with existing rules, and an LXC update rejected `ssh-public-keys` (create-only) | The stack declares no firewall rules or options for clones and keeps the VM ipfilter; the probe-only inbound rule is added by the verify playbook as root | #83 |

## Open findings from the host runs

- Cloud-init restores the default user's passwordless sudo at a VM clone's first boot even though the template seal removed it. It is recorded as an entry gate for the runner-registration phase and has no fix yet. Evidence: [phase 3 index](../evidence/phase3/INDEX.md) (`evidence-vm-clone.txt`).
- A first upgrade attempt over the SSH proxy hop never received the long upgrade's result; async with polling and keep-alives was added and the second run returned it. A laptop entering Modern Standby mid-run suspended the guest and invalidated one attempt; that was an environment event and needed no code change. Evidence: [phase 1 index](../evidence/phase1/INDEX.md) and [phase 2 index](../evidence/phase2/INDEX.md).
- Two R15 rows stay not measured in every phase (a VPN peer's web service and a host in a harvested prefix): no positive control exists on the Windows side, so a block cannot be told from an absent service.

## What this list teaches

Fakes prove logic, not the host's contracts: permission checks that depend on pool context, command surfaces that differ from the documentation, eventually consistent listings, inherited clone state and first-boot services. Where a fix could be tested offline it gained a test or fake behaviour that models what was missed (the fake PVE now serves the status endpoint, refuses to destroy a running guest and can lag its cluster listing), and the host run stays the only proof that the contract holds.
