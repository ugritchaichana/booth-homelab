# 0032. Reach the probe guests over SSH from the Proxmox host with a key that never leaves it

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D56 in docs/platform/requirements.md

## Context

The probe runs inside guests whose own policy drops every inbound connection and every private egress (ADR 0031). Something must start it and read the result without weakening what it measures. The workstation cannot reach the guest subnet directly; the Proxmox host is the only hop.

## Options considered

1. The QEMU guest agent — no inbound rule; the cloud image ships no agent and a container has none.
2. Cloud-init snippets that run the probe at boot — no channel; snippets need provider SSH access to the host, a wider privilege than the API token.
3. SSH from the Proxmox host with a throwaway key generated there — one inbound rule; works for both guest kinds.

## Decision

Option 3.

- `r15-verify.yml --tags r15_keygen` creates the key pair on the host. Only the public half is passed to the stack as `probe_ssh_public_key` and injected through `initialization.user_account.keys`; the private half stays in the host's root account (`probe.yml`, `r15_control_key`).
- Each guest has one inbound rule: tcp/22 from the guest gateway, where host-originated connections come from (`main.tf`, rule with `source = local.guest_network.gateway`). `tests/policy.tftest.hcl` asserts the rule count, port and source, and the playbook's drift check asserts that both rules are enabled.
- The playbook runs `ssh` as tasks on the host with `BatchMode`, `IdentitiesOnly` and keepalives, and deletes the host-key file at the start of each `baseline` run so a re-created guest is not rejected for its new key.
- The probe script and the targets travel over the same connection on standard input; no guest file is written outside `/tmp/r15`. The probe needs only `bash`, `timeout` and `curl`, which the playbook installs through the egress rule when missing.

## Rationale and trade-offs

- Every negative is guest-originated egress, so an inbound allow from the gateway does not change what is tested. For the guest-to-guest rows the host's own connection to the peer's port 22, made in the same run, is the positive control.
- Accepted: a private key without a passphrase sits on the host between apply and destroy; it is deleted by hand after destroy.
- Accepted: the VM login user has passwordless sudo (the image default) and uses it to install packages and to run the probe as root, which the via-gateway rows need to add a route.
- HYPOTHESIS, proven only by the host run: the host's source address for guest-bound traffic is the gateway address, so the one rule admits it.
