# r15-probe stack

A throwaway unprivileged container and a VM on the guest vnet, created only to prove the guest isolation (R15, ADR 0031). Both are linked clones of the golden templates (ADR 0044), so the proof runs on the image runners will use. Apply it for the proof, destroy it afterwards. State handling, secrets and the API forward are the same as the `proxmox-host` stack's (see its README); the wrapper is `scripts/iac/tofu.sh r15-probe <host> <tofu args>`, and the state passphrase is the host's, shared with that stack.

## What it declares

| Object | Value |
|---|---|
| Container, VM | ids, addresses and login users in `probe.yml`; addresses must lie inside the host's guest subnet |
| Clone source | the template module `iac/tofu/modules/proxmox/template-source` resolves one template per class (`template_class` in `probe.yml`) and fails closed unless exactly one matches; `template_pins` pins a class to version N; clones are linked (`full = false`) in pool `homelab` |
| Firewall options, rules, group | inherited from the template (`clone_vmfw_conf`), not declared here; they are the runner-class policy of `iac/policy/runner-class.yml` and `tests/policy.tftest.hcl` asserts the stack declares none. The NIC flag comes from the policy file |
| Control rule | tcp/22 inbound from the guest gateway, added to each clone by `r15-verify.yml` as root before probing, not by this stack |
| VM source filter | `ipfilter-net0` holding the VM's own address |
| Disk | the class disk size read from the Ansible role defaults (`disk_gb`); a clone cannot be smaller than its template |
| Tags | none: Proxmox checks tag permission on `/vms/<id>` without the pool, so a pool-scoped token cannot set tags when it creates a guest |
| Start | created stopped, `start_on_boot` on; `r15-verify.yml` starts them |

The security group is created by the `pve_firewall` role (ADR 0025), so run `site.yml` first, and at least one version of each class must be built (`homelab-template build <class>` on the host). Nothing is downloaded by this stack, so a destroy no longer needs `Datastore.Allocate` (ADR 0035 teardown gap). Changing the clone source or `full` replaces the guest (`ForceNew` in the provider), so a promotion of a new template version replaces the probe guests on the next apply. Measured on the host: the token lists the members of pool `templates` and the clones accept the control channel (requirements rows 57 to 59; ADR 0044).

## Run

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 --tags r15_keygen          # prints TF_VAR_probe_ssh_public_key=...
export TF_VAR_probe_ssh_public_key='ssh-ed25519 ...'
bash scripts/iac/tofu.sh r15-probe pve01 init
bash scripts/iac/tofu.sh r15-probe pve01 apply
```

Then follow `tests/isolation/README.md`. Teardown: `bash scripts/iac/tofu.sh r15-probe pve01 destroy`, then delete the private key on the host.

## Checks without a host

```sh
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123
tofu -chdir=iac/tofu/stacks/r15-probe init -backend=false
tofu -chdir=iac/tofu/stacks/r15-probe validate
tofu -chdir=iac/tofu/stacks/r15-probe test
```

`tests/policy.tftest.hcl` asserts the firewall options, the two rules, the on-boot and NIC flags, the addresses, the source filter and the clone sources (the resolved VMIDs, `full = false`, pool `homelab`, a pin) with literal values, and rejects a private key and an address outside the subnet. `tests/template_source.tftest.hcl` covers the resolution rule of the module: zero matches, two matches, a `current` tag on a non-template, a template outside the pool or the VMID block, an unknown class and a pin. The expected values are literals in the test, not read from `iac/policy/runner-class.yml`.
