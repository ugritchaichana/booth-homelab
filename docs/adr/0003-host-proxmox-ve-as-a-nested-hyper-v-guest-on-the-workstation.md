# 0003. Host Proxmox VE as a nested Hyper-V guest on the workstation

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner and operator
- Decision log: D4, D6, D19, D21, D25 in docs/platform/requirements.md

## Context

The previous platform host was retired by the owner: its Proxmox VE 8.4 is past end of security support, its runner disks filled, and its runners went offline. The owner chose to run the platform on the workstation instead (D4). That machine is a Windows 11 Pro laptop (AMD Ryzen 7 PRO 5850U, 43.8 GiB RAM, one 477 GiB disk, Wi-Fi only) that the owner also uses daily, with WSL2 and Docker Desktop.

Measured before the install (2026-10-06): virtualization-based security and Memory Integrity were already running, so a hypervisor was already present on the host; 159.7 GiB free on `C:` and 24.5 GiB RAM available with WSL stopped. The first agreed budget of 24 GiB RAM and a 140 GiB disk would have left about 0.5 GiB RAM and 19.7 GiB disk (below the 20 GiB floor). Whether nested KVM works on this mobile Zen 3 CPU inside a Hyper-V Linux guest was unproven.

## Options considered

1. Hyper-V — already the hypervisor on this host; nested virtualization is supported for AMD with VM configuration version 9.3 or later (the host default is 12.0); needs the role enabled and one reboot.
2. VMware Workstation or VirtualBox — familiar; the Windows hypervisor already runs on this host (virtualization-based security) and only one software component at a time can use the virtualization hardware, so each would sit on top of it as a second layer.
3. Keep or rent a separate host (the retired machine, or a VPS) — no laptop impact; the owner retired the old host and wanted this machine to be the platform.

For sizing, 24 GiB static RAM and 140 GiB (as first agreed), 20 GiB and 128 GiB, or 16 GiB RAM were compared. For start policy: autostart with Windows, or start on demand.

## Decision

Run Proxmox VE 9 as a Generation 2 Hyper-V VM named `pve01` with nested virtualization on: 12 vCPU, 20 GiB static RAM, a dynamic VHDX capped at 128 GiB (`scripts/hyperv/pve01.psd1:17-19`; `New-PveHost.ps1:386` sets `ExposeVirtualizationExtensions`). The VM starts on demand (`AutomaticStartAction Nothing`, `New-PveHost.ps1:382`); while it is stopped, jobs overflow to hosted runners. Start and stop are a manual script now (`Invoke-PveVm.ps1`); an automatic mechanism is chosen in the runner-controller phase using the measured cold start.

## Rationale and trade-offs

- Hyper-V needs no second hypervisor, which matches the product documentation that nested virtualization is a Hyper-V feature: https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/nested-virtualization.
- 20 GiB leaves about 4.5 GiB for Windows at the measured load, at the edge of the 4 GiB free-RAM signal; the owner chose it over the operator's 16 GiB recommendation. 128 GiB leaves about 28 GiB free after the ISOs. Raise only with load-test evidence.
- Start on demand frees the RAM when the pool is not needed. The operator had recommended autostart; the owner preferred on demand. Speed targets are measured with the VM running.
- Static memory is a choice, not a Hyper-V requirement for nested KVM; the Microsoft text covers Hyper-V inside the guest.
- Measured result (2026-10-06): `svm` count 12, `/dev/kvm` present, `kvm_amd nested` = 1, `systemd-detect-virt` = microsoft, with Memory Integrity on. Nested KVM works, so a VM-based Docker runner class is available (ADR 0015). Cold start: TCP 22 answered 18.1 s after `Start-VM` (#58).
- After the D40 role (ADR 0005, #59) the host runs pve-manager 9.2.21 on kernel 7.0.14-20-pve; nested KVM was re-tested and still passes (`svm` 12, `/dev/kvm`, `nested` = 1).
- Regression gate with the VM running: WSL boots in 2.3 s, Docker Desktop runs `hello-world`, available RAM never below 6049 MB.
- Accepted cost: the laptop is the platform; sleep, shutdown or a full disk takes the pool away. Hyper-V rights for the owner account are covered in ADR 0014.
