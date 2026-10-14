# Load test

Plan: 2 x `test/load7-full-suite` (dotnet), 1 x `test/load7-one-project` (dotnet), 1 x `test/load7-full-rebuild` (dotnet), 1 x `test/load7-flaky-on-proxmox` (dotnet), 1 x `test/load7-always-fails` (dotnet), 8 x `test/load7-full-suite` (angular).
Peak queue: 10 Proxmox jobs queued with 3 runner instances online (3.33 per instance), from 49 samples.
Peak queue per role: dotnet-unit-auto 4 queued with 1 online (4 per runner); dotnet-integration-auto 1 queued with 1 online (1 per runner); workspace-unit-auto 7 queued with 1 online (7 per runner).
Queue ceiling: 2 attempt(s) went to GitHub-hosted because a queue was full; 0 job(s) on Proxmox were cancelled.
Concurrent suites on Proxmox: up to 3 of 17 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 11 job starts, all three (.NET unit, .NET integration, Angular) at 3.

## test/load7-always-fails (dotnet)

- [38561070149](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561070149): failure after 2 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 11488 ms; failed: Test (.NET unit), Report
  - attempt 2 on Proxmox VE Self-Hosted (LXC): outputs 6/7, CoreCompile 7 compiled / 0 reused, build 4776 ms; failed: Test (.NET unit), Report

## test/load7-flaky-on-proxmox (dotnet)

- [38561067538](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561067538): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 6984 ms; failed: none

## test/load7-full-rebuild (dotnet)

- [38561064524](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561064524): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8124 ms; failed: none

## test/load7-full-suite (angular)

- [38561096515](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561096515): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561093488](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561093488): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561090185](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561090185): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561087212](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561087212): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561084093](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561084093): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561079910](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561079910): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561076761](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561076761): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38561073426](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561073426): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load7-full-suite (dotnet)

- [38561057073](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561057073): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 7 compiled / 0 reused, build 9161 ms; failed: none
- [38561053694](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561053694): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 7 compiled / 0 reused, build 17220 ms; failed: none

## test/load7-one-project (dotnet)

- [38561061292](https://github.com/ugritchaichana/booth-homelab/actions/runs/38561061292): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 4/7, CoreCompile 7 compiled / 0 reused, build 10376 ms; failed: none

