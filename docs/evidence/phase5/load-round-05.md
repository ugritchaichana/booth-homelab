# Load test

Plan: 4 x `test/load2-full-suite` (dotnet), 1 x `test/load2-one-project` (dotnet), 1 x `test/load2-full-rebuild` (dotnet), 1 x `test/load2-flaky-on-proxmox` (dotnet), 1 x `test/load2-always-fails` (dotnet), 5 x `test/load2-full-suite` (angular, from 60 s).
Peak queue: 22 Proxmox jobs queued with 3 runner instances online (7.33 per instance), from 41 samples.
Concurrent suites on Proxmox: up to 3 of 19 suite jobs and 2 kinds ran at once; two or more kinds overlapped at 12 job starts, all three (.NET unit, .NET integration, Angular) at 0.

## test/load2-always-fails (dotnet)

- [38523699387](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523699387): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9751 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 5561 ms; failed: Test (.NET unit), Report

## test/load2-flaky-on-proxmox (dotnet)

- [38523696881](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523696881): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8436 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 7293 ms; failed: none

## test/load2-full-rebuild (dotnet)

- [38523694241](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523694241): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8990 ms; failed: none

## test/load2-full-suite (angular)

- [38523881912](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523881912): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38523863017](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523863017): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38523844283](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523844283): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38523826664](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523826664): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38523808399](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523808399): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load2-full-suite (dotnet)

- [38523755178](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523755178): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5494 ms; failed: none
- [38523735411](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523735411): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5694 ms; failed: none
- [38523716862](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523716862): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 4899 ms; failed: none
- [38523690146](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523690146): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5256 ms; failed: none

## test/load2-one-project (dotnet)

- [38523692284](https://github.com/ugritchaichana/booth-homelab/actions/runs/38523692284): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8372 ms; failed: none

