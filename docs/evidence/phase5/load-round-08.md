# Load test

Plan: 4 x `test/load6-full-suite` (angular), 2 x `test/load6-one-project` (dotnet), 20 x `test/load6-full-suite` (angular, from 240 s).
Peak queue: 0 Proxmox jobs queued with 0 runner instances online (0 per instance), from 0 samples.
Annotation: the driver stopped on a dropped API connection before it took a sample, and this report was rebuilt from the API afterwards, so the line above measures nothing. The exact peak, counted from each job's created and started times, was 13 Proxmox jobs queued for `workspace-unit-auto` under a ceiling of 14.
Queue ceiling: 5 attempt(s) went to GitHub-hosted because a queue was full; 0 job(s) on Proxmox were cancelled.
Concurrent suites on Proxmox: up to 3 of 23 suite jobs and 3 kinds ran at once; two or more kinds overlapped at 6 job starts, all three (.NET unit, .NET integration, Angular) at 4.

## test/load6-full-suite (angular)

- [38545168443](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545168443): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545157910](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545157910): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545147086](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545147086): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545135319](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545135319): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545125266](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545125266): success after 1 attempt(s)
  - attempt 1 on GitHub-Hosted (ubuntu-latest): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545114906](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545114906): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545103975](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545103975): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545092553](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545092553): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545081123](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545081123): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545070346](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545070346): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545059148](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545059148): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545047301](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545047301): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545035846](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545035846): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545024632](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545024632): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545012646](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545012646): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38545001003](https://github.com/ugritchaichana/booth-homelab/actions/runs/38545001003): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544990484](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544990484): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544979265](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544979265): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544968286](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544968286): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544957291](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544957291): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544486602](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544486602): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544473617](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544473617): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544459443](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544459443): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none
- [38544445010](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544445010): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs n/a, CoreCompile n/a compiled / n/a reused, build n/a; failed: none

## test/load6-one-project (dotnet)

- [38544462733](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544462733): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 11044 ms; failed: none
- [38544448112](https://github.com/ugritchaichana/booth-homelab/actions/runs/38544448112): success after 1 attempt(s)
  - attempt 1 on Proxmox VE Self-Hosted (LXC): outputs 0/7, CoreCompile 7 compiled / 0 reused, build 13808 ms; failed: none

