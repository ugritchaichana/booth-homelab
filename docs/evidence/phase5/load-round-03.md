# Load test

Plan: 5 x `test/load2-full-suite` (angular), 4 x `test/load2-full-suite` (dotnet), 1 x `test/load2-one-project` (dotnet), 1 x `test/load2-full-rebuild` (dotnet), 1 x `test/load2-flaky-on-proxmox` (dotnet), 1 x `test/load2-always-fails` (dotnet).
Peak queue: 21 Proxmox jobs queued with 3 runner instances online (7 per instance), from 47 samples.
Concurrent suites on Proxmox: up to 3 of 19 suite jobs and 2 kinds ran at once; two or more kinds overlapped at 7 job starts, all three (.NET unit, .NET integration, Angular) at 0.

## test/load2-always-fails (dotnet)

- [38520834575](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520834575): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6440 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 6209 ms; failed: Test (.NET unit), Report

## test/load2-flaky-on-proxmox (dotnet)

- [38520831976](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520831976): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5137 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 6078 ms; failed: none

## test/load2-full-rebuild (dotnet)

- [38520829741](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520829741): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5109 ms; failed: none

## test/load2-full-suite (angular)

- [38520813646](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520813646): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38520810673](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520810673): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38520808587](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520808587): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38520806404](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520806404): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38520804166](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520804166): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load2-full-suite (dotnet)

- [38520822860](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520822860): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 4655 ms; failed: none
- [38520820102](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520820102): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5153 ms; failed: none
- [38520817948](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520817948): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 4882 ms; failed: none
- [38520816039](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520816039): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5291 ms; failed: none

## test/load2-one-project (dotnet)

- [38520826931](https://github.com/ugritchaichana/booth-homelab/actions/runs/38520826931): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8395 ms; failed: none

