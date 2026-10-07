# 0044. Select golden templates fail closed and clone the R15 probe from them

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D71 in docs/platform/requirements.md

## Context

ADR 0040 fixed the contract: consumers resolve a template through the API by tags, fail closed unless exactly one guest matches, and may pin a version that overrides the `current` tag. ADR 0036 put templates in their own pool so the provisioner token can clone them but cannot delete or retag them. Nothing in OpenTofu consumed that contract yet, and the R15 probe still built its guests from two downloaded files (a container template and a cloud image), which is not the image runners will use and left the teardown gap of ADR 0035 (the token cannot free a downloaded volume).

Facts that decide the design, read from the provider source (bpg/proxmox 0.115.0) and the schema of its data sources:

- The data sources `proxmox_virtual_environment_vms` and `proxmox_virtual_environment_containers` return name, node, status, tags, `template` and VMID. They do not return the pool, so the pool is checked through `proxmox_virtual_environment_pool` members.
- In both guest resources the `clone` arguments `vm_id`, `full`, `datastore_id` and `node_name` are `ForceNew`.
- A container clone applies `initialization` (address, DNS, hostname, SSH keys) and the NIC with an update after the clone, and ignores `operating_system`. A VM clone reuses the cloud-init drive the template carries.

## Options considered

1. Look the template up by name or hard-code the VMID in each consumer — simple, but a name is not a trust boundary and a hard-coded VMID bypasses the tag, pool and block checks of ADR 0040.
2. Read the VMID from the host's root state — it is the authoritative record, but it puts a host file on the OpenTofu path and the consumer would trust something other than the Proxmox API it already uses.
3. One module that resolves through the API and refuses unless every rule of ADR 0040 holds, used by every consumer.

## Decision

Option 3: `iac/tofu/modules/proxmox/template-source`, inputs `node`, `class` and an optional `pin` (null by default), output `vmid`.

- Selection: the guests of the class's kind (containers for `lxc-runner`, VMs for `vm-docker`) on the node that carry the marker `homelab-template`, the class and the selector tag. The selector tag is `current`, or `v<pin>` when a pin is set. A pin therefore wins over `current`: the `current` tag is not consulted at all while a pin is set.
- Fail closed: the output `vmid` carries preconditions, and the plan stops unless exactly one guest matches, that guest has `template = true`, is a member of pool `templates`, and has a VMID inside the class block (`vmid_base` to `vmid_base + 99`). A `current` tag on a running guest, a second `current`, a missing version, a template outside the pool or the block, and an unknown class each stop the plan. The window between the two tag writes of a promotion shows zero matches and also stops it (ADR 0040).
- One source of truth: the module reads the class table and the marker from `iac/ansible/roles/pve_templates/defaults/main.yml`, the file that drives the build, so the blocks and kinds cannot drift between builder and consumer. It also returns the class `disk_gb`, because a clone keeps the template's disk size and a smaller declared size would fail.
- Clones are linked: `clone { full = false }`, with the guest in pool `homelab` (never the templates pool). The R15 probe uses the module through `template_class` in `probe.yml` and `template_pins` in the stack (class to N, empty by default).
- The probe no longer downloads anything: both `proxmox_download_file` resources, their variables and the `image_url` output are removed. The runner-class firewall (read from `iac/policy/runner-class.yml`), the tcp/22 control rule from the gateway and the `ipfilter-net0` set (ADR 0032) are unchanged.

## Rationale and trade-offs

- Because `clone.vm_id` is `ForceNew`, a promotion of a new template version changes the resolved VMID and the next apply replaces both probe guests (and their firewall resources, which follow the guest). That suits a throwaway probe. A long-lived consumer should pin, or accept the replacement; the pin is the way to hold a version steady.
- A linked clone depends on its template (ADR 0039). Retention checks that before it deletes a version, so a probe clone of version N blocks deleting N until the probe is destroyed.
- The probe now proves R15 on the image runners will use. Removing the downloads also removes the need for `Datastore.AllocateTemplate`, `Sys.AccessNetwork` and the `Datastore.Allocate` the destroy lacked (ADR 0035).
- The module checks the pool through the pool data source. HYPOTHESIS, settled by the host proof: that the provisioner token, which holds only `VM.Clone` and `VM.Audit` on `/pool/templates`, may read the pool's members. If it cannot, the plan fails closed with a permission error and the privilege question goes back to ADR 0036; nothing is weakened silently.
- HYPOTHESIS, settled by the host proof: that the clones accept the control channel. The build seals `ssh.service` and `ssh.socket` off and removes the login keys (ADR 0038), and a clone's SSH key arrives through `initialization`. Nothing in the template turns sshd on, so the class content or the started-clone hook (ADR 0038) must provide that before R15 baseline can run against a clone. The tests here prove the clone source and the firewall objects, not that channel.
- HYPOTHESIS, settled by the host proof: that a container clone applies `initialization.user_account.keys`, and that `tofu plan` is empty after the first apply (the declared disk block equals the template's disk).
- A test with `mock_provider` proves the rule and the wiring. It does not prove what the Proxmox API returns for tags or for pool members; the host proof compares the resolved VMID with `homelab-template status`.

## Addendum: control channel into the probe clones

Templates stay sealed (ADR 0038): sshd disabled, no login keys. Only the two probe clones get a channel, and the template role is not changed.

- VM clone: `initialization.vendor_data_file_id = "local:snippets/r15-probe-vendor.yaml"` (name in `probe.yml`, `r15_vendor_snippet`). The `r15_keygen` step of `iac/ansible/playbooks/r15-verify.yml` writes that cloud-init vendor-data file as root to `/var/lib/vz/snippets/` with the generated public key; at first boot it installs the key for the default user, runs `ssh-keygen -A` (the seal removed the host keys) and enables and starts `ssh.service`. Storage `local` must allow the `snippets` content type (added in the template role by a separate change). The keygen step must run before the apply, or the clone starts without the file and the apply fails.
- LXC clone: before probing, `r15-verify.yml` runs `pct exec <vmid> -- sh -c ...` as root on the host to install the key for root, generate host keys and enable and start `ssh.service`. `pct exec` attaches into the container as root without any network path, so it is used only for the probe guests listed in `probe.yml`, never for runners.
- Unchanged: runner-class firewall, the tcp/22 control rule from the gateway, `ipfilter-net0`, the phases.
- A test with `mock_provider` proves the VM clone references the snippet. HYPOTHESIS, settled by the host proof: that the snippet is applied to a clone whose template already ran cloud-init once (the instance id changes on clone, so it should run again) and that Debian's `ssh.service` starts once host keys exist.
