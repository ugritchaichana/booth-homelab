# r15-probe stack

A throwaway unprivileged container and a VM on the guest vnet, created only to prove the guest isolation (R15, ADR 0031). Apply it for the proof, destroy it afterwards. State handling, secrets and the API forward are the same as the `proxmox-host` stack's (see its README); the wrapper is `scripts/iac/tofu.sh r15-probe <host> <tofu args>`, and the state passphrase is the host's, shared with that stack.

## What it declares

| Object | Value |
|---|---|
| Container, VM | ids, addresses and login users in `probe.yml`; addresses must lie inside the host's guest subnet |
| Container template | downloaded from the official template mirror with its SHA512 (`lxc_template_name`, `lxc_template_sha512`) |
| Firewall options, group, NIC flag | `iac/policy/runner-class.yml`, shared with the runner stack that comes later (the names the Proxmox API reports) |
| Rules | tcp/22 inbound from the guest gateway only, and the security group `guest-egress` |
| VM source filter | `ipfilter-net0` holding the VM's own address |
| Image | Debian 13 genericcloud from a dated directory with its SHA512 (`image_directory`, `image_sha512`), never `latest` |
| Start | created stopped, `start_on_boot` on; `r15-verify.yml` starts them |

The security group is created by the `pve_firewall` role (ADR 0025), so run `site.yml` first. The token needs the privileges guest creation checks beyond `VM.Config.Network`, and `Datastore.AllocateTemplate` plus `Sys.AccessNetwork` for the two downloads; ADR 0026 does not list all of them, so the first apply on the host is the check.

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

`tests/policy.tftest.hcl` asserts the firewall options, the two rules, the on-boot and NIC flags, the addresses, the source filter and the pinned image with literal values, and rejects `latest`, a private key and an address outside the subnet. The expected values are literals in the test, not read from `iac/policy/runner-class.yml`.
