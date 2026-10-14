# Load test

Plan: 1 x `test/load8-flaky-on-proxmox` (dotnet), 1 x `test/load8-always-fails` (dotnet), 2 x `test/load8-full-suite` (dotnet), 1 x `test/load8-one-project` (dotnet), 1 x `test/load8-full-rebuild` (dotnet), 8 x `test/load8-full-suite` (angular).
Peak queue: 12 Proxmox jobs queued with 3 runner instances online (4 per instance), from 48 samples.
Peak queue per role: dotnet-unit-auto 6 queued with 1 online (6 per runner); dotnet-integration-auto 1 queued with 1 online (1 per runner); workspace-unit-auto 7 queued with 1 online (7 per runner).
Queue ceiling: 0 attempt(s) went to GitHub-hosted because a queue was full; 0 job(s) on Proxmox were cancelled.
Concurrent suites on Proxmox: up to 3 of 18 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 8 job starts, all three (.NET unit, .NET integration, Angular) at 1.

## test/load8-always-fails (dotnet)

- [38568893079](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568893079): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 6/7, CoreCompile 1 compiled / 6 reused, build 4187 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 6142 ms; failed: Test (.NET unit), Report

## test/load8-flaky-on-proxmox (dotnet)

- [38568889364](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568889364): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 6/7, CoreCompile 1 compiled / 6 reused, build 3346 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 7297 ms; failed: none

## test/load8-full-rebuild (dotnet)

- [38568912106](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568912106): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 4202 ms; failed: none

## test/load8-full-suite (angular)

- [38568944452](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568944452): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568939301](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568939301): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568934986](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568934986): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568930886](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568930886): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568927293](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568927293): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568922966](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568922966): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568919380](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568919380): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38568915882](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568915882): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load8-full-suite (dotnet)

- [38568902348](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568902348): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 2135 ms; failed: none
- [38568897159](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568897159): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 2455 ms; failed: none

## test/load8-one-project (dotnet)

- [38568906341](https://github.com/ugritchaichana/booth-homelab/actions/runs/38568906341): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 4/7, CoreCompile 3 compiled / 4 reused, build 4466 ms; failed: none

