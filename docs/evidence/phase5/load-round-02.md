# Load test

Plan: 6 x `test/load-full-suite` (all), 2 x `test/load-one-project` (all), 1 x `test/load-full-rebuild` (all), 1 x `test/load-flaky-on-proxmox` (all), 1 x `test/load-always-fails` (all).
Peak queue: 31 Proxmox jobs queued with 3 runner instances online (10.33 per instance), from 63 samples.
Concurrent suites on Proxmox: up to 3 of 31 suite jobs and 2 kinds ran at once; two or more kinds overlapped at 20 job starts, all three (.NET unit, .NET integration, Angular) at 0.

## test/load-always-fails (all)

- [38517844193](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517844193): failure after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 10848 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 5179 ms; failed: Test (.NET unit), Report

## test/load-flaky-on-proxmox (all)

- [38517842262](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517842262): success after 2 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7859 ms; failed: Test (.NET unit), Report
  - attempt 2 on GitHub-Hosted (ubuntu-latest): outputs 0/1, CoreCompile 7 compiled / 0 reused, build 8186 ms; failed: none

## test/load-full-rebuild (all)

- [38517840411](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517840411): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7226 ms; failed: none

## test/load-full-suite (all)

- [38517834586](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517834586): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6544 ms; failed: none
- [38517832752](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517832752): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7271 ms; failed: none
- [38517830629](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517830629): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6362 ms; failed: none
- [38517828763](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517828763): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9405 ms; failed: none
- [38517826759](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517826759): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 7983 ms; failed: none
- [38517824652](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517824652): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 11041 ms; failed: none

## test/load-one-project (all)

- [38517838231](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517838231): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 8509 ms; failed: none
- [38517836413](https://github.com/ugritchaichana/booth-homelab/actions/runs/38517836413): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 9761 ms; failed: none

