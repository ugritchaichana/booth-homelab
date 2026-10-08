# Blocking conditions

While any row is `open`, the composite is capped at 49 (standard section 2, condition 4).
The scorecard parses the table below: the second column is `open` or `closed`.

| condition | status | note | date |
|---|---|---|---|
| Exposed credential | open | not yet closed by a recorded purge and rotation | 2026-10-06 |
| Untrusted execution | closed | one persistent self-hosted runner container is registered (ADR 0060); its job-start hook `scripts/ci/runner-guard.sh` fails every job before its first step unless the event is a push, a dispatch, a schedule or a pull request from a branch of this repository (`tests/isolation/test-runner-guard.sh`), and `sdet-ci.yml` sends fork pull requests to hosted runners; reopens if the hook is removed or a runner registers without it | 2026-10-08 |
| Unsupported software | closed | The retired host ran Proxmox VE 8.4, past end of security support (2026-08-31); the current platform runs PVE 9.2 (wiki page 08, Runtime Support and Upgrade Plan). That host's two runners were deregistered on 2026-10-08 (docs/evidence/closeout/owner-gaps-readback.txt) | 2026-10-08 |
| False green | closed | selector fails closed, shown by run 37341728563 attempt 2 | 2026-10-06 |
