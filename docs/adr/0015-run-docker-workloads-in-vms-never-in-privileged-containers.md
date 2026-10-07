# 0015. Run Docker workloads in VMs, never in privileged containers

- Status: Accepted
- Date: 2026-10-06
- Deciders: owner
- Decision log: D9 in docs/platform/requirements.md (question Q5)

## Context

The platform serves a public repository, so runner jobs can execute code the owner did not write. The owner wants a Docker-capable runner class as a baseline capability, even though the repository's own tests use no Docker today (`git grep` for Testcontainers, a Docker client and `docker run` over `apps`, `scripts/apps` and `tests` returned 0 lines on 2026-10-06; test packages are xunit and coverlet only).

The tree still carries the earlier approach: containers with `nesting = true` and `keyctl = true` running Docker (`iac/tofu/main.tf:35`, `iac/ansible/roles/runner_dotnet/`; both removed, ADR 0020). Proxmox states: "We do not support Docker containers on top of LXC containers" (https://forum.proxmox.com/threads/docker-integration.175870, read 2026-09-30). A privileged container shares the host kernel with whatever the job runs.

Before 2026-10-06 it was unknown whether nested KVM works on this machine (mobile Zen 3 CPU, Hyper-V as the outer hypervisor, Memory Integrity on).

## Options considered

1. A VM runner class (needs nested KVM) — Docker runs under its own guest kernel; heavier than a container and costs reserved RAM and boot time.
2. A privileged LXC container with Docker — light and fast, but unsupported by Proxmox, and job code gets close to host-kernel access. Unacceptable for public-repository code.
3. Docker jobs run only on GitHub-hosted runners — safe and free for public repositories, but no self-hosted Docker capability and no baseline to reuse elsewhere.

## Decision

Docker workloads run in a VM runner class. Never in a privileged container, for any public-repository code. If nested KVM had failed, Docker jobs would have gone to hosted runners (option 3).

## Rationale and trade-offs

- Measured 2026-10-06 on the installer kernel (6.17.2-1-pve), with Memory Integrity on: `systemd-detect-virt` reports `microsoft`, `egrep -c "vmx|svm" /proc/cpuinfo` = 12, `/dev/kvm` exists, and `kvm_amd` `nested` = 1 (measured over SSH, 2026-10-06; #58). The earlier plan to test with Memory Integrity off was therefore not needed.
- Re-measured 2026-10-06 after the package upgrade moved the host to pve-manager 9.2.21 on kernel 7.0.14-20-pve: `grep -Ec 'vmx|svm' /proc/cpuinfo` = 12, `/dev/kvm` present, `kvm_amd` `nested` = 1 (#59). Nested-KVM performance overhead is unmeasured.
- Not yet proven end to end: a job running `docker run hello-world` inside a VM runner. It is the acceptance proof for this class and belongs to the template and runner phases.
- Accepted cost: a VM class takes more RAM and start time than a container, inside a fixed static-memory budget for the Proxmox VM (20 GiB).
- Revisit if Proxmox begins to support Docker in containers, or if a later kernel upgrade breaks nested KVM; in that case option 3 applies without further decision.
