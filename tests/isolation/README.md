# Isolation tests

Every `test-*.sh` file is plain Bash, takes no argument, exits non-zero on the first broken expectation and runs in the `iac-ci.yml` Ansible job (CI, no host). What each one proves, with its happy, bad and edge cases: `docs/knowledge/test-catalogue.md`.

| File | Purpose |
|---|---|
| `r15-probe.sh` | Runs inside a probe guest or the cache container: one `PROBE` line per target, one `SUMMARY`, exit 0 only if every measured row holds. Not a CI test. |
| `test-r15-probe.sh` | Runs `r15-probe.sh` with a stubbed `timeout`, `curl`, `id` and `ip`, plus real sockets and a real timeout, including the cache rows and the cache-container scope. |
| `test-r15-verify-cache.sh` | Syntax-checks `r15-verify.yml` and renders its commands: the cache address reaches both runner probes, the probe runs inside the cache container, the cleanup sits in an `always` section, and a new probe generation never meets the previous host keys. |
| `test-cluster-fw-render.sh` | Renders `cluster.fw.j2` and checks the deny set against an RFC list, the rule order and, with a cache endpoint, the cache accept. |
| `test-guest-fw-guard.sh` | Runs the guest firewall guard against a fake `pvesh`: violators are stopped, compliant guests, templates and other nodes are left alone, per-vnet policy for the guests and cache vnets. |
| `test-pve-api-identity-grants.sh` | Checks that `VM.Clone` is granted only on the templates pool and that the vnet grants match the expected set. |
| `test-role-pve-host.sh` | Runs the `pve_host` tasks against fake modules and command stubs (`lib/role-fakes.sh`): the three repositories (enterprise off, `pve-no-subscription` on, all signed by the keyring, suite override), the cache refresh only on a change, the full upgrade, the reboot conditions, the boot-kernel choice (pin, version order, empty list), the failure after a reboot, and the nested-KVM assert on each bad reading. |
| `test-role-hyperv-guest.sh` | Runs the `hyperv_guest` tasks the same way: the `install hv_sock /bin/false` drop-in (one line per module), the unload, and the asserts that stop the play for an installed or running KVP, VSS or file-copy daemon, a loaded blocked module and a modprobe plan that would load it. |
| `test-template-build.sh` | Runs the template orchestrator against fakes of `pvesh`, `qm`, `pct`, `lvs` and `systemctl` (`lib/fake-pve.py`): one case per pre-start attribute, promotion, rollback, retention, the pass-marker gate, the thresholds. |
| `test-template-guest-step.sh` | Runs the non-root guest step against a fake `ssh`: the connection options, the size and marker checks, the seal as the last connection, the manifest diff, the key cleanup. |
| `test-template-finalize.sh` | Runs the in-guest `finalize.sh`, `seal.sh` and `run.sh` on a fake root: cleanup, planted secrets, the allowlist, the pass marker, the seal, Ansible with `-c local`. |
| `test-template-units.sh` | Checks the shipped guest unit keeps `IPAddressDeny=any`, a non-root `User=` and the sandbox set, with mutations that must fail, and that the rendered configuration follows `runner-class.yml`. |
| `test-template-content.sh`, `test-template-content-vm.sh` | Lint the class bundles (`lib/lint-template-content.py`): every artifact pinned by hash, no TCP daemon socket in the `vm-docker` class. |
| `test-cache-service-role.sh` | Checks the rendered `bazel-remote` unit and the role's pins, and that the writer password never appears in a unit. |
| `test-cache-start-gate.sh` | The cache container is started only after its firewall reads back compliant. |
| `test-cache-verify-cas.sh` | A blob whose content does not match its name is quarantined, not served. |
| `test-cache-wait-for-address.sh` | The start waits for the configured address using the routing table file, not `ip`. |
| `test-cache-writer-secret.sh` | `cache-writer-secret.sh` stores the credential through SOPS and GitHub, never on a command line or in output. |
| `targets.example.env` | Row format with documentation addresses. Copy to `targets.env`, which git ignores. |

## Targets file

One row per target: `label=scope kind host port expect expect_red control`.

- `scope`: `all`, `runner` (lxc and vm, never the cache container), `lxc`, `vm` or `cache`, the guest that runs the row (`cache` runs only inside the cache container, which `r15-verify.yml` probes when the host entry has `cache_endpoint`; `CACHE_ADDR` and `CACHE_PORT` add the two cache rows for the runner guests). `kind`: `tcp`, `tcp6`, or `tcpvia` (the peer is routed through the gateway first, which needs root; it is the path that bypasses port isolation).
- `expect` applies with the firewall on (`open` or `blocked`), `expect_red` in phase `red-first` (`open`, `blocked` or `refused`). `refused` means the path is open but nothing listens, an immediate reset: a row that is dropped with the firewall on and refused with it off proves a filter, not an absent service.
- `control` is `True` when a working connection to the same target was measured from somewhere else: `scripts/hyperv/Test-R15Controls.ps1` from Windows (`CONTROL <label> <target> True`), the `red-first` run for rows only the Proxmox layer blocks, or `channel:<guest>`, which `r15-verify.yml` replaces with `True` or `False` from the host's own connection to that guest in the same run (the guest-to-guest rows).

## Reading the output

`PROBE <label> <kind> <host:port> <expected> <actual> <verdict>`. The probe connects with bash `/dev/tcp` under `timeout`: `actual` is `open` (connected), `dropped` (no answer before the timeout), `unreachable`, `refused` (an immediate reset: something answered) or `error`. A `blocked` row that is `open` or `refused` fails whatever its `control`. A silent one (`dropped`, `unreachable`) passes with control `True` and prints `NOT MEASURED`, uncounted, without it. `PROBE egress_https` fetches the Debian mirror and must read 200 in every run. `SUMMARY negatives_blocked=N/N positives_ok=M/M egress_curl=200`; a run with no measured negative exits 1.

## Procedure

Exact commands are in `iac/tofu/stacks/r15-probe/README.md` (keygen, apply, teardown) and `RUNBOOK.md` section 11. In order:

1. Run `Test-R15Controls.ps1`, copy the `True` rows into the `control` column.
2. `red-first` (attended: it stops the node firewall; a timer restarts it after 10 minutes if the play dies, and the run refuses while any non-probe guest is running), then `baseline`, then restart the container and run `after-pct-reboot`, then `after-pve-reboot`, then `after-host-reboot`:

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<directory for the results>
```

3. Attribution while the firewall is on, on the host: `grep DROP /var/log/pve-firewall.log` for each external target, and `tcpdump -ni vmbr0 -c 1 host <target>` during the probe, which must capture nothing.

## Checks without a host

```sh
bash -n tests/isolation/r15-probe.sh
for t in tests/isolation/test-*.sh; do bash "$t"; done
```

The render tests need `ansible`; install the pinned toolchain from `iac/ansible/README.md` first.

## What a green run does not show

- Which layer blocked an external row; only the `red-first` run separates the Proxmox layer from the Windows layer.
- Which layer blocked a guest-to-guest row: port isolation survives `pve-firewall stop`, so the guest-to-guest rows, direct and via the gateway, read `blocked` in `red-first` too (requirements row 51).
- The harvested VPN prefix and a VPN peer's web service: no host inside them answers from Windows, so a block cannot be told from an absent service. They read `NOT MEASURED` in every phase (requirements rows 38, 42, 52, 66).
- UDP: the probe tests TCP only.
