# 0069. Size trial guests with fixed memory and no start on boot

- Status: Accepted
- Date: 2026-10-20
- Deciders: owner and operator
- Decision log: D102 in docs/platform/requirements.md
- Builds on: ADR 0017, ADR 0055

## Context

A runner-design comparison needs two guests shaped like the machines it models: 4 vCPU each, with the larger role holding twice the memory of the smaller. The workstation cannot give the Proxmox VM more than its 20 GiB (ADR 0003) while it is in use (27.9 GiB free of 43.8 GiB with the VM off, 2026-10-20), so the owner chose to keep 20 GiB and scale the trial guests' memory while keeping the modelled CPU.

Two defaults of the guest stack (ADR 0055) do not fit:

- Every catalog flavor sets `balloon_mb` to half its memory (`iac/tofu/flavors.json`), and the stack passes it as `floating` (`iac/tofu/stacks/guest/main.tf:119`). With 15 GiB of trial guests on a 20 GiB host, host usage passes the 80% point at which Proxmox reclaims balloon memory, so a guest could shrink mid-trial and the measurement would change underneath it.
- Every guest starts on boot (`main.tf:104`). Trial guests started on every boot would take 15 GiB next to the cache, the probes, the demo guests and the role runners.

## Options considered

1. Change the existing flavors — affects every guest and breaks the meaning of the cloud-named sizes.
2. A `lab` provider in the catalog with fixed-memory sizes, plus an optional per-guest `on_boot` in the guest list defaulting to true — existing guests and tests are unchanged.
3. Create trial VMs outside the stack with `qm` — the guard would stop any VM whose firewall drifts, addresses and VMIDs would not be checked for collisions, and nothing records the fleet (ADR 0055, option 3).

## Decision

Option 2. `lab/trial-4c-5g` and `lab/trial-4c-10g` have no `balloon_mb`, so the flavor module returns 0 and ballooning is off. A guest entry may set `on_boot: false`; the value reaches `on_boot` of a VM and `start_on_boot` of a container. The two trial guests use slots 7 and 8 with `on_boot: false`.

## Consequences

- Trial guests start only when an operator starts them; the other guests that start on boot (demo, probes, role runners) are stopped for a trial window and started again after it.
- The trial guests' memory is 0.625 of the modelled machines'; CPU is unchanged.
- Proof: `iac/tofu/stacks/guest/tests/guest.tftest.hcl`, run `a_guest_can_opt_out_of_start_on_boot_and_a_lab_flavor_has_no_balloon`; with `on_boot` hardcoded to true it fails, with the change every run passes.
