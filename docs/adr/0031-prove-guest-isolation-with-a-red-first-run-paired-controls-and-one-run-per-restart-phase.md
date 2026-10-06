# 0031. Prove guest isolation with a red-first run, paired controls and one run per restart phase

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D55 in docs/platform/requirements.md

## Context

R15 says a guest must not reach the host, the home network, the VPN or the management network, and the proof must survive restarts. Earlier measurements (after install and after the workstation reboot) exposed three ways a negative test misleads: a timeout toward a target nothing listens on proves nothing (the guest-to-host port 53 rows were unpaired), an offline guest passes every negative, and two layers (Hyper-V port ACLs, the Proxmox firewall) block the same traffic, so one row cannot say which layer did it. Per-guest firewall options belong to the guest change (ADR 0025), so this change owns the first guests that carry them.

## Options considered

1. Re-run the old shell probes by hand from the Proxmox host — no new code; the host is not a guest, so it never exercises the guest policy.
2. Probe from throwaway guests that carry exactly the runner-class policy, with paired controls and a red-first run — new code and two guests; the measured path is the real one.
3. Assert the firewall files only (the ADR 0027 checks) — fast and offline; says nothing about what the kernel and the SDN do with them.

## Decision

Option 2.

- `iac/tofu/stacks/r15-probe/`: one unprivileged container and one VM, on boot, static addresses in the guest subnet, firewall on, `policy_in` and `policy_out` DROP, `ipfilter`, `log_level_out info`, security group `guest-egress`, and one inbound rule (ADR 0032). The policy is declared once in `probe.yml`; `tests/policy.tftest.hcl` hard-codes the expected values, so editing the declaration fails a named test.
- `tests/isolation/r15-probe.sh` runs inside a guest and prints one `PROBE` line per target and a `SUMMARY` line (`r15-probe.sh:102`). A row expected to be blocked counts only when its `control` column is `True`; otherwise it prints `NOT MEASURED` and stays out of the counts (`r15-probe.sh:81`). A run with no measured negative fails. Every run ends with an HTTPS fetch of the Debian mirror that must return 200 (`r15-probe.sh:94`), so an offline guest cannot pass.
- Red-first: `pve-firewall stop`, then the rows that only the Proxmox layer blocks must be `open` and the external rows must stay blocked, which attributes the external rows to the Windows layer alone. `pve-firewall start` runs in an `always:` block (`iac/ansible/playbooks/r15-verify.yml:316`).
- Phases: `baseline`, `after-pct-reboot`, `after-pve-reboot`, `after-host-reboot`, `red-first`. The playbook also reads each guest's firewall options, rules, NIC flags and VM source filter back from the host and fails on drift from `probe.yml`.
- `scripts/hyperv/Test-R15Controls.ps1` produces the Windows-side control lines.

## Rationale and trade-offs

- Pairing is a column the operator fills, not something the guest can compute: the control runs on another machine. The script enforces the rule; it cannot check the operator's entry.
- Guests are created stopped so none runs before its firewall options exist; the playbook starts them and `start_on_boot` restarts them. `started` is ignored in plans, or the next plan would stop them.
- IPv6 egress is denied by `policy_out DROP` alone, because the group holds IPv4 sets only (ADR 0027).
- Measured offline: eight `tofu test` runs pass, and six single-attribute mutations (policy_out, ipfilter, log level, NIC flag, control-rule source, on-boot) each fail one named run; `tests/isolation/test-r15-probe.sh` passes 12 cases, including an open negative, a refused connection, an offline guest and a missing control.
- HYPOTHESIS, proven only by the host run: SNAT works with the firewall on; the download resource id is accepted as `import_from`; the token holds every `VM.Config.*` privilege guest creation needs (ADR 0026 lists none beyond `VM.Config.Network`); the guest images ship `nc` and `curl` or can install them through the egress rule.
- Not covered: the harvested VPN prefix row stays `NOT MEASURED` until a peer inside it answers from Windows.
