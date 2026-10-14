# Load test

Plan: 4 x `test/load8-full-suite` (dotnet), 1 x `test/load8-one-project` (dotnet), 1 x `test/load8-full-rebuild` (dotnet), 20 x `test/load8-full-suite` (angular).
Peak queue: 19 Proxmox jobs queued with 3 runner instances online (6.33 per instance), from 54 samples.
Peak queue per role: dotnet-unit-auto 6 queued with 1 online (6 per runner); dotnet-integration-auto 1 queued with 1 online (1 per runner); workspace-unit-auto 13 queued with 1 online (13 per runner).
Queue ceiling: 3 attempt(s) went to GitHub-hosted because a queue was full; 0 job(s) on Proxmox were cancelled.
Concurrent suites on Proxmox: up to 3 of 29 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 22 job starts, all three (.NET unit, .NET integration, Angular) at 6.

## test/load8-full-rebuild (dotnet)

- [38578879385](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578879385): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 5055 ms; failed: none

## test/load8-full-suite (angular)

- [38579124303](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579124303): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579113621](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579113621): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579101378](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579101378): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579090309](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579090309): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579079084](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579079084): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579068001](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579068001): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579055411](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579055411): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579043479](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579043479): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579031357](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579031357): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579019141](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579019141): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38579006381](https://github.com/ugritchaichana/booth-homelab/actions/runs/38579006381): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578992989](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578992989): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578981499](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578981499): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578969088](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578969088): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578956696](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578956696): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578944983](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578944983): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578933269](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578933269): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578917191](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578917191): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578900379](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578900379): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38578883715](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578883715): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load8-full-suite (dotnet)

- [38578928943](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578928943): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 2658 ms; failed: none
- [38578912977](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578912977): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 1586 ms; failed: none
- [38578895854](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578895854): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 2077 ms; failed: none
- [38578869811](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578869811): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 7/7, CoreCompile 0 compiled / 7 reused, build 1659 ms; failed: none

## test/load8-one-project (dotnet)

- [38578875053](https://github.com/ugritchaichana/booth-homelab/actions/runs/38578875053): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 4/7, CoreCompile 3 compiled / 4 reused, build 4168 ms; failed: none

