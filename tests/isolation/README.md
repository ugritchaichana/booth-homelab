# Isolation tests

| File | Purpose |
|---|---|
| `test-cluster-fw-render.sh` | Renders `cluster.fw.j2` and checks the deny set against an RFC list (CI, no host). |
| `r15-probe.sh` | Runs inside a probe guest: one `PROBE` line per target, one `SUMMARY`, exit 0 only if every measured row holds. |
| `test-r15-probe.sh` | Runs `r15-probe.sh` against stubbed `nc` and `curl` (CI, no host). |
| `targets.example.env` | Row format with documentation addresses. Copy to `targets.env`, which git ignores. |

## Targets file

One row per target: `label=scope kind host port expect expect_red control`.

- `scope`: `all`, `lxc` or `vm`, the guest that runs the row. `kind`: `tcp` or `tcp6`.
- `expect` applies with the firewall on, `expect_red` in phase `red-first`: `open` or `blocked`.
- `control` is `True` when a working connection to the same target was measured from somewhere else: `scripts/hyperv/Test-R15Controls.ps1` from Windows (`CONTROL <label> <target> True`), the `red-first` run for rows only the Proxmox layer blocks, or the host's own connection to the guest recorded by the playbook for guest-to-guest rows.

## Reading the output

`PROBE <label> <kind> <host:port> <expected> <actual> <verdict>`. `actual` is `open`, `dropped` (silent timeout), `unreachable`, `refused` (the target answered) or `error`. A `blocked` row passes on `dropped` or `unreachable`; `refused` fails, because something answered. A `blocked` row without `control` True prints `NOT MEASURED` and is not counted. `PROBE egress_https` fetches the Debian mirror and must read 200 in every run. `SUMMARY negatives_blocked=N/N positives_ok=M/M egress_curl=200`; a run with no measured negative exits 1.

## Procedure

Exact commands are in `iac/tofu/stacks/r15-probe/README.md` (keygen, apply, teardown). In order:

1. Run `Test-R15Controls.ps1`, copy the `True` rows into the `control` column.
2. `red-first`, then `baseline`, then restart the container and run `after-pct-reboot`, then `after-pve-reboot`, then `after-host-reboot`:

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<directory for the results>
```

3. Attribution while the firewall is on, on the host: `grep DROP /var/log/pve-firewall.log` for each external target, and `tcpdump -ni vmbr0 -c 1 host <target>` during the probe, which must capture nothing.

## Checks without a host

```sh
bash -n tests/isolation/r15-probe.sh
bash tests/isolation/test-r15-probe.sh
```

## What a green run does not show

- Which layer blocked an external row; only the `red-first` run separates the Proxmox layer from the Windows layer.
- The harvested VPN prefix, until a peer inside it answers from Windows.
- UDP: the probe tests TCP only.
