# Load test

Plan: 6 x `test/load-full-suite` (all), 2 x `test/load-one-project` (all), 1 x `test/load-full-rebuild` (all), 1 x `test/load-flaky-on-proxmox` (all), 1 x `test/load-always-fails` (all).
Peak queue: 29 Proxmox jobs queued with 3 runner instances online (9.67 per instance), from 55 samples.
Concurrent suites on Proxmox: up to 3 of 30 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 18 job starts, all three (.NET unit, .NET integration, Angular) at 1.

## test/load-always-fails (all)

- [38516088499](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516088499): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 1 compiled / 2 reused, build 1802 ms; failed: Build (.NET), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 6033 ms; failed: Test (.NET unit), Report

## test/load-flaky-on-proxmox (all)

- [38516086098](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516086098): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6243 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 7627 ms; failed: none

## test/load-full-rebuild (all)

- [38516083764](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516083764): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7826 ms; failed: none

## test/load-full-suite (all)

- [38516075256](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516075256): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5718 ms; failed: none
- [38516072553](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516072553): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5953 ms; failed: none
- [38516069909](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516069909): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7286 ms; failed: none
- [38516067265](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516067265): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9094 ms; failed: none
- [38516065146](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516065146): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8984 ms; failed: none
- [38516063155](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516063155): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 15653 ms; failed: none

## test/load-one-project (all)

- [38516080544](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516080544): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6548 ms; failed: none
- [38516077901](https://github.com/ugritchaichana/booth-homelab/actions/runs/38516077901): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 12194 ms; failed: none

