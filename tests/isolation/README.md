# Isolation tests

Every `test-*.sh` file is plain Bash, takes no argument, exits non-zero on the first broken expectation and runs in the `iac-ci.yml` Ansible job (CI, no host). What each one proves, with its happy, bad and edge cases: [`docs/knowledge/test-catalogue.md`](../../docs/knowledge/test-catalogue.md).

| File | Purpose |
|---|---|
| `r15-probe.sh` | Runs inside a probe guest or the cache container: one `PROBE` line per target, one `SUMMARY`, exit 0 only if every measured row holds. Not a CI test. |
| `targets.example.env` | Row format with documentation addresses. Copy to `targets.env`, which git ignores. |

## Targets file

One row per target: `label=scope kind host port expect expect_red control`.

- `scope`: `all`, `runner` (lxc and vm, never the cache container), `lxc`, `vm` or `cache`, the guest that runs the row (`cache` runs only inside the cache container, which `r15-verify.yml` probes when the host entry has `cache_endpoint`; `CACHE_ADDR` and `CACHE_PORT` add the two cache rows for the runner guests). `kind`: `tcp`, `tcp6`, or `tcpvia` (the peer is routed through the gateway first, which needs root; it is the path that bypasses port isolation).
- `expect` applies with the firewall on (`open` or `blocked`), `expect_red` in phase `red-first` (`open`, `blocked` or `refused`). `refused` means the path is open but nothing listens, an immediate reset: a row that is dropped with the firewall on and refused with it off proves a filter, not an absent service.
- `control` is `True` when a working connection to the same target was measured from somewhere else: `scripts/hyperv/Test-R15Controls.ps1` from Windows (`CONTROL <label> <target> True`), the `red-first` run for rows only the Proxmox layer blocks, or `channel:<guest>`, which `r15-verify.yml` replaces with `True` or `False` from the host's own connection to that guest in the same run (the guest-to-guest rows).

## Reading the output

`PROBE <label> <kind> <host:port> <expected> <actual> <verdict>`. The probe connects with bash `/dev/tcp` under `timeout`: `actual` is `open` (connected), `dropped` (no answer before the timeout), `unreachable`, `refused` (an immediate reset: something answered) or `error`. A `blocked` row that is `open` or `refused` fails whatever its `control`. A silent one (`dropped`, `unreachable`) passes with control `True` and prints `NOT MEASURED`, uncounted, without it. `PROBE egress_https` fetches the Debian mirror and must read 200 in every run. `SUMMARY negatives_blocked=N/N positives_ok=M/M egress_curl=200`; a run with no measured negative exits 1.

## Procedure

Exact commands are in `iac/tofu/stacks/r15-probe/README.md` (keygen, apply, teardown) and `RUNBOOK.md`, Build from zero, R15 verification. In order:

1. Run `Test-R15Controls.ps1`, copy the `True` rows into the `control` column.
2. `red-first` (attended: it stops the node firewall; a timer restarts it after 10 minutes if the play dies, and the run refuses while any non-probe guest is running), then `baseline`, then restart the container and run `after-pct-reboot`, then `after-pve-reboot`, then `after-host-reboot`:

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<directory for the results>
```

3. Attribution while the firewall is on, on the host: `grep DROP /var/log/pve-firewall.log` for each external target, and `tcpdump -ni vmbr0 -c 1 host <target>` during the probe, which must capture nothing.

## Checks without a host

Run `bash -n tests/isolation/r15-probe.sh` and every `test-*.sh` (first command of [RUNBOOK.md, Offline suites (no host)](../../RUNBOOK.md#41-offline-suites-no-host)). The render tests need `ansible`; install the pinned toolchain from `iac/ansible/README.md` first.

## What a green run does not show

- Which layer blocked an external row; only the `red-first` run separates the Proxmox layer from the Windows layer.
- Which layer blocked a guest-to-guest row: port isolation survives `pve-firewall stop`, so the guest-to-guest rows, direct and via the gateway, read `blocked` in `red-first` too (requirements row 51).
- The harvested VPN prefix and a VPN peer's web service: no host inside them answers from Windows, so a block cannot be told from an absent service. They read `NOT MEASURED` in every phase (requirements rows 38, 42, 52, 66).
- UDP: the probe tests TCP only.
