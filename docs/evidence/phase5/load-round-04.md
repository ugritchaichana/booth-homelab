# Load test

Plan: 5 x `test/load2-full-suite` (angular), 4 x `test/load2-full-suite` (dotnet), 1 x `test/load2-one-project` (dotnet), 1 x `test/load2-full-rebuild` (dotnet), 1 x `test/load2-flaky-on-proxmox` (dotnet), 1 x `test/load2-always-fails` (dotnet).
Peak queue: 19 Proxmox jobs queued with 3 runner instances online (6.33 per instance), from 40 samples.
Concurrent suites on Proxmox: up to 3 of 19 suite jobs and 2 kinds ran at once; two or more kinds overlapped at 10 job starts, all three (.NET unit, .NET integration, Angular) at 0.

## test/load2-always-fails (dotnet)

- [38522520411](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522520411): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 10684 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 8284 ms; failed: Test (.NET unit), Report

## test/load2-flaky-on-proxmox (dotnet)

- [38522505865](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522505865): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9407 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 8197 ms; failed: none

## test/load2-full-rebuild (dotnet)

- [38522491073](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522491073): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 10059 ms; failed: none

## test/load2-full-suite (angular)

- [38522639976](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522639976): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38522605500](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522605500): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38522568811](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522568811): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38522535072](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522535072): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38522445018](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522445018): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load2-full-suite (dotnet)

- [38522622588](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522622588): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5177 ms; failed: none
- [38522587792](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522587792): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5646 ms; failed: none
- [38522549821](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522549821): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5604 ms; failed: none
- [38522460256](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522460256): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8828 ms; failed: none

## test/load2-one-project (dotnet)

- [38522475390](https://github.com/ugritchaichana/booth-homelab/actions/runs/38522475390): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9730 ms; failed: none

