# 0058. Size trial guests with fixed memory and no start on boot

- Status: Accepted
- Date: 2026-10-20
- Deciders: owner and operator
- Decision log: D89 in docs/platform/requirements.md
- Builds on: ADR 0017, ADR 0055

## Context

A runner-design comparison needs two guests sized like the machines it models: 4 vCPU with 16 GiB and 4 vCPU with 8 GiB, 24 GiB in total. The Proxmox VM has 20 GiB at rest (ADR 0003) and is raised to 28 GiB only while trials run, then restored.

Two defaults of the guest stack (ADR 0055) do not fit:

- Every catalog flavor sets `balloon_mb` to half its memory (`iac/tofu/flavors.json`), and the stack passes it as `floating` (`iac/tofu/stacks/guest/main.tf:119`). With 24 GiB of guests on a 28 GiB host the host passes the 80% usage point at which Proxmox reclaims balloon memory, so a guest's memory could shrink mid-trial and the measurement would no longer match the modelled machine.
- Every guest starts on boot (`main.tf:104`). After a trial the host is back at 20 GiB, so the next boot would try to start 24 GiB of trial guests next to the demo guests.

## Options considered

1. Change the existing flavors — affects every guest and breaks the meaning of the cloud-named sizes.
2. A `lab` provider in the catalog with fixed-memory sizes, plus an optional per-guest `on_boot` in the guest list defaulting to true — existing guests and tests are unchanged.
3. Create trial VMs outside the stack with `qm` — the guard would stop any VM whose firewall drifts, addresses and VMIDs would not be checked for collisions, and nothing records the fleet (ADR 0055, option 3).

## Decision

Option 2. `lab/trial-4c-8g` and `lab/trial-4c-16g` have no `balloon_mb`, so the flavor module returns 0 and ballooning is off. A guest entry may set `on_boot: false`; the value reaches `on_boot` of a VM and `start_on_boot` of a container. The two trial guests use slots 3 and 4 with `on_boot: false`.

## Consequences

- Trial guests start only when an operator starts them, on a host sized for them.
- The demo guests still start on boot; during a trial window they are stopped first so the trial guests have the memory.
- Proof: `iac/tofu/stacks/guest/tests/guest.tftest.hcl`, run `a_guest_can_opt_out_of_start_on_boot_and_a_lab_flavor_has_no_balloon`; with `on_boot` hardcoded to true it fails (`Failure! 25 passed, 1 failed.`), with the change all 26 runs pass.
