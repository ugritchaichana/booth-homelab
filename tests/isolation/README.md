# Isolation tests

| File | Purpose |
|---|---|
| `test-cluster-fw-render.sh` | Renders `cluster.fw.j2` and checks the deny set against an RFC list (CI, no host). |
| `r15-probe.sh` | Runs inside a probe guest: one `PROBE` line per target, one `SUMMARY`, exit 0 only if every measured row holds. |
| `test-r15-verify-cache.sh` | Syntax-checks `r15-verify.yml` and renders its commands: the cache address reaches both runner probes, the probe runs inside the cache container, and the cleanup that removes the script and targets sits in an `always` section (CI, no host). |
| `test-r15-probe.sh` | Runs `r15-probe.sh` with a stubbed `timeout`, `curl`, `id` and `ip`, plus real sockets and a real timeout (CI, no host). |
| `test-template-build.sh` | Runs the template orchestrator against fakes of `pvesh`, `qm`, `pct`, `lvs` and `systemctl` (`lib/fake-pve.py`): one case per pre-start attribute, promotion, rollback, retention, the pass-marker gate, the thresholds (CI, no host). |
| `test-template-guest-step.sh` | Runs the non-root guest step against a fake `ssh`: the connection options, the size and marker checks, the seal as the last connection, the manifest diff, the key cleanup (CI, no host). |
| `test-template-finalize.sh` | Runs the in-guest `finalize.sh`, `seal.sh` and `run.sh` on a fake root: cleanup, planted secrets, the allowlist, the pass marker, the seal, Ansible with `-c local`, the playbook syntax check (CI, no host). |
| `test-template-units.sh` | Checks the shipped guest unit keeps `IPAddressDeny=any`, a non-root `User=` and the sandbox set, with mutations that must fail, and that the rendered configuration follows `runner-class.yml` (CI, no host). |
| `targets.example.env` | Row format with documentation addresses. Copy to `targets.env`, which git ignores. |

## Targets file

One row per target: `label=scope kind host port expect expect_red control`.

- `scope`: `all`, `lxc`, `vm` or `cache`, the guest that runs the row (`cache` runs only inside the cache container, which `r15-verify.yml` probes when the host entry has `cache_endpoint`; `CACHE_ADDR` and `CACHE_PORT` add the two cache rows for the runner guests). `kind`: `tcp`, `tcp6`, or `tcpvia` (the peer is routed through the gateway first, which needs root; it is the path that bypasses port isolation).
- `expect` applies with the firewall on, `expect_red` in phase `red-first`: `open` or `blocked`.
- `control` is `True` when a working connection to the same target was measured from somewhere else: `scripts/hyperv/Test-R15Controls.ps1` from Windows (`CONTROL <label> <target> True`), the `red-first` run for rows only the Proxmox layer blocks, or `channel:<guest>`, which `r15-verify.yml` replaces with `True` or `False` from the host's own connection to that guest in the same run (the guest-to-guest rows).

## Reading the output

`PROBE <label> <kind> <host:port> <expected> <actual> <verdict>`. The probe connects with bash `/dev/tcp` under `timeout`: `actual` is `open` (connected), `dropped` (no answer before the timeout), `unreachable`, `refused` (an immediate reset: something answered) or `error`. A `blocked` row that is `open` or `refused` fails whatever its `control`. A silent one (`dropped`, `unreachable`) passes with control `True` and prints `NOT MEASURED`, uncounted, without it. `PROBE egress_https` fetches the Debian mirror and must read 200 in every run. `SUMMARY negatives_blocked=N/N positives_ok=M/M egress_curl=200`; a run with no measured negative exits 1.

## Procedure

Exact commands are in `iac/tofu/stacks/r15-probe/README.md` (keygen, apply, teardown). In order:

1. Run `Test-R15Controls.ps1`, copy the `True` rows into the `control` column.
2. `red-first` (attended: it stops the node firewall; a timer restarts it after 10 minutes if the play dies, and the run refuses while any non-probe guest is running), then `baseline`, then restart the container and run `after-pct-reboot`, then `after-pve-reboot`, then `after-host-reboot`:

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
- Which layer blocked a guest-to-guest row: port isolation survives `pve-firewall stop`, so the direct rows read `blocked` in `red-first` too, and the via-gateway rows' `red-first` value is a HYPOTHESIS until the first run.
- The harvested VPN prefix, until a peer inside it answers from Windows.
- UDP: the probe tests TCP only.
