# 0055. Create flavor-sized guests from a declarative list with one command

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: not yet recorded in docs/platform/requirements.md
- Builds on: ADR 0017, ADR 0030, ADR 0044, ADR 0047

## Context

ADR 0017 put every size in `iac/tofu/flavors.json` and the lookup in `iac/tofu/modules/flavor/`, but only a test called the module (`iac/tofu/stacks/proxmox-host/tests/flavor.tftest.hcl`). The Proxmox web interface has no instance-type field, so an operator still typed cores, memory and disk by hand. The owner wants to pick a size such as `aws/t3.medium` and get a guest of that size with one command, and to find the guest in the interface by what it does and which template it came from.

Constraints from earlier decisions:

- The host guard stops any guest without `firewall=1` on every NIC, `ipfilter` and the guest vnet policy (ADR 0047). The R15 probe satisfies it by cloning a template and declaring only the NIC flag and, for a VM, an `ipfilter-net0` set (`iac/tofu/stacks/r15-probe/main.tf:44`, `:112`, `:150`).
- Guest addresses are assigned by hand and nothing detects a duplicate; the accepted loss of ADR 0030 (`docs/adr/0030-*.md:32`) was to be revisited when guests are created in bulk.
- Linked clones inherit the template's tags, `current` included; the probe overwrites them (ADR 0044).
- State is one file per stack and host (`scripts/iac/tofu.sh:43`).

## Options considered

1. Flavor variables on the existing probe stack — no new stack, but the probe is throwaway and applied only during the isolation proof (ADR 0031), so real guests would share its state and its destroy.
2. A new root stack that reads a guest list file — guests are data, the stack owns no sizes, and a wrapper can edit the list.
3. One tofu command with `-var` flags per guest — nothing to commit, so the fleet exists only in someone's shell history and a second apply with different flags destroys the first guest.
4. A computed address (hash or position in the list) — no number to maintain, but a hash collides at a few guests and a position shifts every later guest's address and VMID when one is removed.

## Decision

Option 2, with a stored slot instead of a computed address.

**Guest list.** `iac/tofu/stacks/guest/guests.yml`, YAML like the inventory and the probe data. It is keyed host, then role, and shipped empty (`guests: {}`). Per guest: `flavor` (`provider/instance`), `template_class` (`lxc-runner` or `vm-docker`), optional `template_version` (a whole number) and `slot`. The stack reads the section of `var.host` only (`locals.tf:18`), so a second host does not receive the first host's guests. `var.guests_file` points a test at a fixture.

**Size.** Sizes come only from `modules/flavor`, one instance per distinct flavor (`main.tf:11`). The stack reads `flavors.json` keys, never sizes, for the unknown-flavor check (`locals.tf:33-35`). `tofu test` cannot expect a failure from a module output: `You cannot expect failures from module.flavor["aws/t3.nonexistent"].cores. You can only expect failures from checkable objects such as input variables, output values, check blocks, managed resources and data sources.` The key check gives the failure to a root output (`outputs.tf:26`), and a guest with an unknown flavor never instantiates the module.

**Budget.** `var.guest_budget` is the largest size one guest may have; its defaults are the whole Proxmox VM of ADR 0003 (12 vCPU, 20 GiB RAM, 128 GiB disk), so a flavor beyond the host is rejected at plan time on each resource (`variables.tf:45`, `main.tf:79`). The defaults are a ceiling, not a plan to fill the host: nothing sums the guests (see Consequences).

**Disk.** A clone disk only grows, so a flavor disk below the template disk fails the plan (`main.tf:84`). `aws/t3.nano` (10 GB, `iac/tofu/flavors.json:8`) fits the `lxc-runner` template (8 GB) and not `vm-docker` (20 GB) (`iac/ansible/roles/pve_templates/defaults/main.yml:48`, `:59`).

**Firewall and network.** The same as the probe: unprivileged container, `bridge = local.guest_network.vnet`, `firewall` from `iac/policy/runner-class.yml`, `ipfilter-net0` holding the VM's own address, and no firewall rules or options declared (clones inherit the template's) (`main.tf:25`, `:53`, `:134`, `:176`). Guests are linked clones in pool `homelab`, created stopped with start on boot, `started` ignored so the guard can stop one without tofu fighting it (`main.tf:72`, `:157`).

**Addresses and VMIDs.** A slot from 1 to 99 drives both: the address is host `100 + slot` of the guest subnet (`10.99.16.101` to `10.99.16.199`) and the VMID is `9500 + slot` (`locals.tf:15-16`). The range is clear of the gateway `.1`, the probes `.21` and `.22`, the template build addresses `.30` and `.31` (`defaults/main.yml:44`, `:54`), and of VMIDs 9050 (cache), 9101 and 9102 (probes) and the template blocks 9200 to 9399. A future third template class must not take `vmid_base: 9500`. The wrapper stores the lowest free slot in the file, so removing a guest never moves another; the stack rejects two guests with one slot and a slot outside 1 to 99 (`outputs.tf:36-45`). This closes the accepted loss of ADR 0030 for guests of this stack.

**Names.** The Proxmox name and the container hostname are `<role>-<template class>-v<N>`, for example `demo-lxc-runner-v6`, where `N` is the version actually cloned: the pin, or the version tagged `current` at plan time. `modules/proxmox/template-source` returns it as `version`, read from the template's `vN` tag (`outputs.tf:36`). The name must be a lowercase hostname of at most 63 characters starting with a letter; a role that breaks that, or two roles that compose the same name, fail the plan (`outputs.tf:16-25`). The role stays the identity of the guest in state, so the name changes in place when a new template version is promoted, and the clone source change replaces the guest as it does for the probe.

**Tags.** Every guest carries `flavor-guest`, `flavor-<provider>-<instance>` and `src-<class>-v<N>`. The flavor tag is lowercased with every character outside `a-z0-9_.+-` replaced by a hyphen, because a Proxmox tag has no `/` and lowercases on read (`aws/t3.medium` becomes `flavor-aws-t3.medium`, `azure/Standard_B2s` becomes `flavor-azure-standard_b2s`). The list is sorted before it is sent (`locals.tf:42-50`).

**Command.** `scripts/iac/new-guest.sh --flavor F --template CLASS [--role ROLE] [--version vN] [--host H] [--apply]` validates the flavor against `flavors.json`, the class against `pve_templates_classes`, the role and the version, edits the list and runs `scripts/iac/tofu.sh guest <host> init` then `plan` (or `apply`, which still asks for confirmation). Rejections exit 1 with one line and leave the file unchanged; a usage error exits 2. The host defaults to the only inventory host. `--name` is an alias of `--role`. A repeated role updates the entry and keeps its slot; leaving out `--version` on an update returns the guest to the current template.

## Consequences

- `tests/isolation/test-new-guest.sh` and `iac/tofu/stacks/guest/tests/guest.tftest.hcl` run in `iac-ci.yml` without a live API; the wrapper test replaces `tofu.sh` with a logger through `HOMELAB_TOFU_SH`.
- Changing a flavor in `flavors.json` changes the size of every guest of that flavor at its next apply (ADR 0017).
- Nothing sums the guests: ten guests that each fit `guest_budget` can still exceed the host. An aggregate memory check is the next step if the list grows.
- A guest has no login path from this stack. The templates are sealed with their login keys and sshd disabled (ADR 0038), and the stack declares no `user_account` or vendor data. Starting a guest and reaching it is the runner controller's job.
- HYPOTHESIS, settled by the first host apply: the token can set tags in the update after the clone, as the probe does (ADR 0044); and the provider returns the three tags in sorted order, so a second plan shows no change. If the second plan shows a tag diff, the sort moves to the provider's order.
- HYPOTHESIS, settled by the first host apply: resizing a clone disk from the template size to the flavor size works for an unprivileged container and for a `scsi0` VM disk with the token's grants.
- The stack and its tests are written against a mocked provider; the host apply is the proof that Proxmox accepts the objects.
