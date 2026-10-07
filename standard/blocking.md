# Blocking conditions

While any row is `open`, the composite is capped at 49 (standard section 2, condition 4).
The scorecard parses the table below: the second column is `open` or `closed`.

| condition | status | note | date |
|---|---|---|---|
| Exposed credential | open | not yet closed by a recorded purge and rotation | 2026-10-06 |
| Untrusted execution | open | public repository; runners registered in persistent mode | 2026-10-06 |
| Unsupported software | open | Proxmox VE 8.4 is past end of security support (2026-08-31) | 2026-10-06 |
| False green | closed | selector fails closed, shown by run 37341728563 attempt 2 | 2026-10-06 |
