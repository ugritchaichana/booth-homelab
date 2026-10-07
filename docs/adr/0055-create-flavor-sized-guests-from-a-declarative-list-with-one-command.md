# 0055. Create flavor-sized guests from a declarative list with one command

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D83 in docs/platform/requirements.md
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

**Guest list.** `iac/tofu/stacks/guest/guests.yml`, YAML like the inventory and the probe data. It is keyed host, then `<role>-<template class>` (for example `demo-lxc-runner`), and shipped empty (`guests: {}`). Per guest: `flavor` (`provider/instance`), `template_class` (`lxc-runner` or `vm-docker`), optional `template_version` (a whole number) and `slot`. The stack reads the section of `var.host` only (`locals.tf:18`), so a second host does not receive the first host's guests. `var.guests_file` points a test at a fixture.

**Size.** Sizes come only from `modules/flavor`, one instance per distinct flavor (`main.tf:11`). The stack reads `flavors.json` keys, never sizes, for the unknown-flavor check (`locals.tf:34-36`). `tofu test` cannot expect a failure from a module output: `You cannot expect failures from module.flavor["aws/t3.nonexistent"].cores. You can only expect failures from checkable objects such as input variables, output values, check blocks, managed resources and data sources.` The key check gives the failure to a root output (`outputs.tf:31`), and a guest with an unknown flavor never instantiates the module.

**Budget.** `var.guest_budget` is the largest size one guest may have; its defaults are the whole Proxmox VM of ADR 0003 (12 vCPU, 20 GiB RAM, 128 GiB disk), so a flavor beyond the host is rejected at plan time on each resource (`variables.tf:45`, `main.tf:84`). The defaults are a ceiling, not a plan to fill the host: nothing sums the guests (see Consequences).

**Disk.** A clone disk only grows, so a flavor disk below the template disk fails the plan (`main.tf:89`). `aws/t3.nano` (10 GB, `iac/tofu/flavors.json:8`) fits the `lxc-runner` template (8 GB) and not `vm-docker` (20 GB) (`iac/ansible/roles/pve_templates/defaults/main.yml:48`, `:59`).

**Firewall and network.** The same as the probe: unprivileged container, `bridge = local.guest_network.vnet`, `firewall` from `iac/policy/runner-class.yml`, `ipfilter-net0` holding the VM's own address, and no firewall rules or options declared (clones inherit the template's) (`main.tf:30`, `:58`, `:139`, `:181`). Guests are linked clones in pool `homelab`, created stopped with start on boot, `started` ignored so the guard can stop one without tofu fighting it (`main.tf:77`, `:162`).

**Addresses and VMIDs.** A slot from 1 to 99 drives both: the address is host `100 + slot` of the guest subnet (`10.99.16.101` to `10.99.16.199`) and the VMID is `9500 + slot` (`locals.tf:15-16`). The range is clear of the gateway `.1`, the probes `.21` and `.22`, the template build addresses `.30` and `.31` (`defaults/main.yml:44`, `:54`), and of VMIDs 9050 (cache), 9101 and 9102 (probes) and the template blocks 9200 to 9399. A future third template class must not take `vmid_base: 9500`. The wrapper stores the lowest free slot in the file, so removing a guest never moves another; the stack rejects two guests with one slot and a slot outside 1 to 99 (`outputs.tf:41-50`). This closes the accepted loss of ADR 0030 for guests of this stack.

**Names.** The Proxmox name and the container hostname are `<role>-<template class>-v<N>`, for example `demo-lxc-runner-v6`, where `N` is the version actually cloned: the pin, or the version tagged `current` at plan time. `modules/proxmox/template-source` returns it as `version`, read from the template's `vN` tag (`outputs.tf:36`). The name must be a lowercase hostname of at most 63 characters starting with a letter; a role that breaks that, or two roles that compose the same name, fail the plan (`outputs.tf:16-30`). The role stays the identity of the guest in state, so the name changes in place when a new template version is promoted, and the clone source change replaces the guest as it does for the probe. The key of the list and of the resources is `<role>-<template class>`, so one role can have a guest of each class (`demo-lxc-runner-v6` and `demo-vm-docker-v7`); the plan rejects a key that does not end in its `template_class`. A `moved` block carries the first guest, created under the key `demo`, to `demo-lxc-runner` without replacing it (`main.tf:18-21`); delete it once every host has applied.

**Tags.** Every guest carries `flavor-guest`, `flavor-<provider>-<instance>` and `src-<class>-v<N>`. The flavor tag is lowercased with every character outside `a-z0-9_.+-` replaced by a hyphen, because a Proxmox tag has no `/` and lowercases on read (`aws/t3.medium` becomes `flavor-aws-t3.medium`, `azure/Standard_B2s` becomes `flavor-azure-standard_b2s`). The list is sorted before it is sent (`locals.tf:43-51`).

**Command.** `scripts/iac/new-guest.sh --flavor F --template CLASS [--role ROLE] [--version vN] [--host H] [--apply]` validates the flavor against `flavors.json`, the class against `pve_templates_classes`, the role and the version, edits the list and runs `scripts/iac/tofu.sh guest <host> init` then `plan` (or `apply`, which still asks for confirmation). Rejections exit 1 with one line and leave the file unchanged; a usage error exits 2. The host defaults to the only inventory host. `--name` is an alias of `--role`. A repeated role updates the entry and keeps its slot; leaving out `--version` on an update returns the guest to the current template. With `--apply` the command applies with `-auto-approve` (the flag is the approval, so it works without a terminal), then runs `plan -detailed-exitcode`; on exit 2 it applies once more and the final plan must exit 0, otherwise it fails with one line. Without `--apply` it only plans.

## Consequences

- `tests/isolation/test-new-guest.sh` and `iac/tofu/stacks/guest/tests/guest.tftest.hcl` run in `iac-ci.yml` without a live API; the wrapper test replaces `tofu.sh` with a logger through `HOMELAB_TOFU_SH`.
- Changing a flavor in `flavors.json` changes the size of every guest of that flavor at its next apply (ADR 0017).
- Nothing sums the guests: ten guests that each fit `guest_budget` can still exceed the host. An aggregate memory check is the next step if the list grows.
- A guest has no login path from this stack. The templates are sealed with their login keys and sshd disabled (ADR 0038), and the stack declares no `user_account` or vendor data. Starting a guest and reaching it is the runner controller's job.
- MEASURED on the host (pve01, provider 0.115.0): the plan of the first guest showed 1 to add with hostname `demo-lxc-runner-v6`, 2 cores, 4096 MB, size 30 and address 10.99.16.101. The first apply created VMID 9501 in 1 s with `cores: 2`, `memory: 4096`, `swap: 0`, tags `flavor-aws-t3.medium;flavor-guest;src-lxc-runner-v6`, `bridge=guests,firewall=1`, `unprivileged: 1`, stopped. Setting tags in the update after the clone worked and the tags read back sorted with no drift.
- MEASURED, and it disproves the earlier hypothesis: the provider ignores the disk size when it clones a container. The first apply left `rootfs size=8G`; the second plan exited 2 with `~ disk { size = 8 -> 30 }`; a second apply resized it in 23 s (`size=32212254720`) and the third plan exited 0. A clone therefore needs two applies, which `new-guest.sh --apply` runs by itself. The VM clone takes the flavor disk at creation: 9502 `demo-vm-docker-v7` read back `scsi0 ... size=30G` after the first apply.
- MEASURED: the provider reads a VM's `pool_id` back as empty although the VM is a member of pool `homelab` (`pvesh get /pools/homelab` lists 9502). Every plan then proposed adding it to the pool, and that update fails with `HTTP 403 ... (/pool/homelab, Pool.Allocate)`. Containers read the pool back correctly. The VM resource therefore ignores changes to `pool_id`: the clone joins the pool at creation, and granting `Pool.Allocate` to the provisioner token would widen it beyond guest lifecycle.
- The stack and its tests are written against a mocked provider; the host apply is the proof that Proxmox accepts the objects.
