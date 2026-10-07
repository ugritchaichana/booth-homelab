# 0031. Prove guest isolation with a red-first run, paired controls and one run per restart phase

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D55 in docs/platform/requirements.md

## Context

R15 says a guest must not reach the host, the home network, the VPN or the management network, and the proof must survive restarts. Earlier measurements (after install and after the workstation reboot) exposed three ways a negative test misleads: a timeout toward a target nothing listens on proves nothing (the guest-to-host port 53 rows were unpaired), an offline guest passes every negative, and several layers (Hyper-V port ACLs, the Proxmox firewall, bridge port isolation) block overlapping traffic, so one row cannot say which layer did it. Per-guest firewall options belong to the guest change (ADR 0025), so this change owns the first guests that carry them.

## Options considered

1. Re-run the old shell probes by hand from the Proxmox host — no new code; the host is not a guest, so it never exercises the guest policy.
2. Probe from throwaway guests that carry the runner-class policy, with paired controls and a red-first run — new code and two guests; the measured path is the real one.
3. Assert the firewall files only (the ADR 0027 checks) — fast and offline; says nothing about what the kernel and the SDN do with them.

## Decision

Option 2.

- The runner-class policy (firewall options, security group, NIC firewall flag) lives in `iac/policy/runner-class.yml`. `stacks/r15-probe` reads it, and so must the later runner stack; the playbook's drift check reads the same file. `tests/policy.tftest.hcl` compares the plan with literal values written in the test, so editing the policy file fails a named run. The probe-only part (guest ids, addresses, control port and key) stays in `stacks/r15-probe/probe.yml`.
- Guests are created stopped. `r15-verify.yml` reads every guest's firewall options, rules (each rule enabled), NIC set, bridge, NIC firewall flag and VM source filter first (`r15-verify.yml:113`) and only then starts guests (`:242`); on drift it stops any running probe guest and fails.
- `tests/isolation/r15-probe.sh` runs inside a guest and prints a `PROBE` line per target and a `SUMMARY` line (`r15-probe.sh:124`). It connects with bash `/dev/tcp` under `timeout` (`:40`): exit 0 is `open`, a timeout is `dropped`, a fast failure is `refused`. A row expected blocked fails when it opens or answers with a reset, whatever its control (`:100`); a silent one counts only when its `control` column is `True`, otherwise it prints `NOT MEASURED` and stays out of the counts. A run with no measured negative fails. Every run fetches the Debian mirror and must read 200 (`:116`), so an offline guest cannot pass.
- Red-first runs the node-wide `pve-firewall stop`, because the host's own input policy must be down for the gateway rows to read `open`; disabling only the probe guests' firewalls would leave that policy in place. The stop is guarded: it refuses to run while any other guest is running, arms a transient timer that restarts the firewall in 10 minutes even if the controller dies (`r15-verify.yml:349`), bounds the probe with a task timeout and SSH keepalives, and after the restart waits for `enabled/running`, drops the guest subnet's conntrack entries and cancels the timer (`:395`).
- Guest-to-guest rows come in pairs. Direct: port isolation sits below the firewall and survives `pve-firewall stop`, so it expects `blocked` in every phase. Via-gateway (`tcpvia`): the probe routes the peer through the gateway, the path that bypasses isolation, and expects `blocked` with the firewall on. Their control is the host's own connection to the peer in the same run, written into the targets by the playbook (`channel:<guest>`).
- Phases: `baseline`, `after-pct-reboot`, `after-pve-reboot`, `after-host-reboot`, `red-first`. `scripts/hyperv/Test-R15Controls.ps1` produces the Windows-side control lines.
- The container template is downloaded by the stack from the official template mirror with its SHA512 (`proxmox_download_file`, content `vztmpl`); the host's template list was empty.

## Rationale and trade-offs

- Pairing is a column the operator fills, except the channel rows: the control runs on another machine, so the script enforces the rule and cannot check the entry.
- IPv6 egress is denied by `policy_out DROP` alone, because the group holds IPv4 sets only (ADR 0027).
- Measured offline: nine `tofu test` runs pass and nine single-attribute mutations each fail one named run; `tests/isolation/test-r15-probe.sh` passes 22 cases, including real sockets (open listener, reset from a closed port) and a real timeout, and three mutations of the probe each fail named cases. The drift assertions were run against fake `pvesh` output with eight mutations.
- HYPOTHESIS, proven only by the host run: the via-gateway row reads `blocked` even with the firewall stopped, because the peer's reply returns directly between the two isolated ports; if it reads `open`, set that row's `expect_red` to `open` on that evidence. Also unproven: SNAT works with the firewall on; the download resource id is accepted as `import_from`; the token holds every `VM.Config.*` privilege guest creation needs; `pvesh` reports `enable` and the declared options in the shape the drift check reads.
- Not covered: the harvested VPN prefix row stays `NOT MEASURED` until a peer inside it answers from Windows.
