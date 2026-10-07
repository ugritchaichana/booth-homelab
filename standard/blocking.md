# Blocking conditions

While any row is `open`, the composite is capped at 49 (standard section 2, condition 4).
The scorecard parses the table below: the second column is `open` or `closed`.

| condition | status | note | date |
|---|---|---|---|
| Exposed credential | open | not yet closed by a recorded purge and rotation | 2026-10-06 |
| Untrusted execution | open | public repository; runners registered in persistent mode | 2026-10-06 |
| Unsupported software | open | The retired host ran Proxmox VE 8.4, past end of security support (2026-08-31); the current platform runs PVE 9.2 (wiki page 08, Runtime Support and Upgrade Plan). Open because that host's two runners are still registered with the repository; the owner's explicit go to deregister them (Phase 6) closes it | 2026-10-07 |
| False green | closed | selector fails closed, shown by run 37341728563 attempt 2 | 2026-10-06 |
