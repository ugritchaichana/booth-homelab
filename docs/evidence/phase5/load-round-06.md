# Load test

Plan: 2 x `test/load3-full-suite` (dotnet), 1 x `test/load3-one-project` (dotnet), 1 x `test/load3-full-rebuild` (dotnet), 1 x `test/load3-flaky-on-proxmox` (dotnet), 1 x `test/load3-always-fails` (dotnet), 8 x `test/load3-full-suite` (angular).
Peak queue: 14 Proxmox jobs queued with 6 runner instances online (2.33 per instance), from 58 samples.
Peak queue per role: dotnet-unit-auto 6 queued with 1 online (6 per runner); dotnet-integration-auto 1 queued with 1 online (1 per runner); workspace-unit-auto 7 queued with 1 online (7 per runner).
Concurrent suites on Proxmox: up to 3 of 18 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 7 job starts, all three (.NET unit, .NET integration, Angular) at 3.

## test/load3-always-fails (dotnet)

- [38530419161](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530419161): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 18943 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 7783 ms; failed: Test (.NET unit), Report

## test/load3-flaky-on-proxmox (dotnet)

- [38530416197](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530416197): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 18581 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 8907 ms; failed: none

## test/load3-full-rebuild (dotnet)

- [38530413522](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530413522): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 10527 ms; failed: none

## test/load3-full-suite (angular)

- [38530444052](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530444052): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530440463](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530440463): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530437452](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530437452): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530434424](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530434424): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530431704](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530431704): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530428496](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530428496): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530424805](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530424805): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38530421821](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530421821): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load3-full-suite (dotnet)

- [38530407120](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530407120): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 17254 ms; failed: none
- [38530403990](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530403990): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 11304 ms; failed: none

## test/load3-one-project (dotnet)

- [38530410564](https://github.com/ugritchaichana/booth-homelab/actions/runs/38530410564): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 10272 ms; failed: none

