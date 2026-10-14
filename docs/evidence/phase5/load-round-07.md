# Load test

Plan: 22 x `test/load5-full-suite` (angular), 3 x `test/load5-one-project` (dotnet, from 30 s).
Peak queue: 17 Proxmox jobs queued with 6 runner instances online (2.83 per instance), from 46 samples.
Peak queue per role: dotnet-unit-auto 3 queued with 1 online (3 per runner); dotnet-integration-auto 1 queued with 1 online (1 per runner); workspace-unit-auto 14 queued with 1 online (14 per runner).
Queue ceiling: 4 attempt(s) went to GitHub-hosted because a queue was full; 0 job(s) on Proxmox were cancelled.
Concurrent suites on Proxmox: up to 3 of 24 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 11 job starts, all three (.NET unit, .NET integration, Angular) at 3.

## test/load5-full-suite (angular)

- [38542400021](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542400021): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542388103](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542388103): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542377202](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542377202): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542366237](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542366237): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542354207](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542354207): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542341998](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542341998): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542330206](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542330206): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542317548](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542317548): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542306057](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542306057): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542294708](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542294708): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542283501](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542283501): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542271912](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542271912): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542258397](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542258397): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542245523](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542245523): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542230115](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542230115): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542218666](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542218666): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542205819](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542205819): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542193378](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542193378): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542181226](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542181226): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542167792](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542167792): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542157065](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542157065): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38542146114](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542146114): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load5-one-project (dotnet)

- [38542265122](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542265122): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 6364 ms; failed: none
- [38542252116](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542252116): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 11402 ms; failed: none
- [38542237973](https://github.com/ugritchaichana/booth-homelab/actions/runs/38542237973): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 13870 ms; failed: none

