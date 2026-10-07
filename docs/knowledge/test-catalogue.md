# Test catalogue

One row per test file. "Happy" is the accepted path, "bad" is an input that must be refused, "edge" is a boundary or a failure of a dependency. A row marked **host-only proof** is a claim the CI run cannot make: only the run on the real Proxmox host shows it, and the evidence index named in the last column holds the transcript.

Commands run in the operator toolchain (WSL Debian) from the repository root. Tests that render or run Ansible need the pinned toolchain:

```
python3 -m pip install --require-hashes -r iac/ansible/requirements-ci.txt
ansible-galaxy collection install -r iac/ansible/requirements.yml
```

## CI jobs

| Job (workflow) | Runs |
|---|---|
| OpenTofu Lint & Validate (`iac-ci.yml`) | `tofu fmt -check`, tflint, then `init -backend=false`, `validate` and `test` in every root module under `iac/tofu` |
| Ansible Lint, Syntax & Molecule (`iac-ci.yml`) | ansible-lint (production profile), `--syntax-check` of every playbook, every `tests/isolation/test-*.sh`, then Molecule for the `base` role |
| Verify Affected Graph Selector Engine (`affected-selector-ci.yml`) | `tests/verify-affected-graph.sh`, `tests/verify-affected-graph.ps1`, then three mutants of the selector that each must fail one named scenario |
| Evidence Publisher Tests & Published-Text Check (`evidence-ci.yml`) | `tests/evidence/test_publish.py`, then `publish.py --check docs/evidence docs/knowledge` |

## Shell tests under `tests/isolation/`

All of them are plain Bash, take no argument and exit non-zero on the first broken expectation. They run in CI in the Ansible job's isolation step, which loops over `tests/isolation/test-*.sh`. Local command: `bash tests/isolation/<file>`.

| File | Proves | Host-only proof / evidence |
|---|---|---|
| `test-cluster-fw-render.sh` | Happy: `cluster.fw.j2` renders the `guest-egress` rules in order (`OUT DROP` to the host-routed set, then `OUT ACCEPT` to public IPv4), the RFC special-use deny prefixes, the host-routed and management ipsets, `local_network` pinned to the management source, and cluster options enabled with `policy_in: DROP`. Bad: any deviation (a missing deny prefix, a public sample inside the deny set, a wrong ipset or rule order) fails the run with a `FAIL:` line. Needs `ansible`. | The firewall behaving on the real PVE layer is host-only: [phase 2 index](../evidence/phase2/INDEX.md) (R15 red-first and baseline rows) |
| `test-guest-fw-guard.sh` | Happy: a compliant guest and a guest off the guests vnet are left alone, a stopped violator and a guest of another node are not touched, and nothing is ever started. Bad: a NIC without `firewall=1`, a `policy_out` of ACCEPT, a disabled egress group rule, an extra enabled `OUT ACCEPT`, an extra `IN ACCEPT` from anywhere, or inbound tcp/22 from a non-gateway source is stopped and leaves a violation marker. Edge: an unreadable guest is stopped only on the third consecutive run; a failing guest list stops nothing and exits 4; markers clear when guests comply. Runs against a fake `pvesh`. | The guard stopping a half-created VM on the host is host-only: [phase 2 index](../evidence/phase2/INDEX.md) (converge and host-baseline rows) |
| `test-pve-api-identity-grants.sh` | Happy: the declared roles grant `VM.Clone` only on the templates pool and nothing else there. Bad: any wider grant breaks the role's own assertions, so the run fails. Needs `ansible-playbook`. | Token 403 and 200 outcomes are host-only: [phase 3 index](../evidence/phase3/INDEX.md) (`proof-rollback-token.txt`, `evidence-token-more.txt`) |
| `test-r15-probe.sh` | Happy: the probe prints one `PROBE` line per row and a `SUMMARY` with every negative blocked and the egress positive at 200. Bad: a paired negative that opens, a refused connection, a name error, an offline guest, a positive that does not open, an unpaired row that opens or resets all exit 1 and name the row. Edge: no route counts as blocked; an unpaired silent row is `NOT MEASURED` and uncounted; no measured negative at all fails; `tcpvia` without root and an unknown phase are usage errors (exit 2); a real timeout against a silent target is `dropped`. Stubs `timeout`, `curl`, `id`, `ip`. | **host-only proof** that the rows are really blocked: [phase 3 index](../evidence/phase3/INDEX.md) (`r15-baseline-lxc.txt`, `r15-baseline-vm.txt`), [phase 2 index](../evidence/phase2/INDEX.md) (red-first, baseline, after-reboot rows) |
| `test-template-build.sh` | Happy: both classes build three versions through the orchestrator against `lib/fake-pve.py`; rollback swaps current and previous; a build after rollback keeps the rollback target. Bad: storage below the minimum refuses with exit 3 and creates nothing; a second build under the lock exits 3; an unknown class exits 2; a symlink planted in the work directory refuses the build; a non-build guest in the class block, or a build-named guest in a pool, is never destroyed. Edge: retention never deletes a version with a dependent clone and keeps the recorded current and previous when tags drift; a failing firewall call destroys the half-built guest unstarted; cleanup trusts the live guest state over a lagging cluster listing; a planted credential means no conversion to a template. | **host-only proof** of the real builds, retention and rollback: [phase 3 index](../evidence/phase3/INDEX.md) (`build-weekly-*`, `build-lxc-retention.txt`, `proof-rollback-token.txt`, `evidence-rollback-vm.txt`) |
| `test-template-guest-step.sh` | Happy: the non-root guest step builds with the expected ssh options, writes the manifest as fetched, and the pass marker carries the build id. Bad: a failed seal, a seal that never says `SEAL-OK`, an in-guest scan failure, a marker for another build id, an empty marker, a non-JSON or non-object manifest each fail the step and write no pass marker. Edge: the seal is the last connection; a connection that closes after `SEAL-OK` is a success; a manifest of exactly 1000 bytes is accepted and one byte more is refused; a malformed address opens no connection; sshd answering on the second try still builds; control characters never reach the step output. Uses a fake `ssh`. | **host-only proof** of the in-guest scan and seal: [phase 3 index](../evidence/phase3/INDEX.md) (`build-weekly-*`) |
| `test-template-finalize.sh` | Happy: a clean guest passes, is cleaned (machine-id truncated, random seed and journal removed) and keeps the channel open for the two fetches; the seal then removes keys, build output and the NOPASSWD sudo entry and locks the login user's password; `run.sh` runs Ansible with `-c local` inside the guest. Bad: a planted secret, a non-allowlisted test key, an allowlisted path with changed content, a missing manifest leave no pass marker (a stale marker is removed). Edge: a malformed build id exits 2; `run.sh` installs and later purges Ansible only when the guest had none. Runs on a fake root. | **host-only proof**: the in-guest secret scan on real toolchain files (the runner's bundled npm config tripped it on the host): [phase 3 index](../evidence/phase3/INDEX.md) (`build-weekly-1.txt`, `build-weekly-2.txt`) |
| `test-template-units.sh` | Happy: the shipped guest unit with its rendered drop-in satisfies every sandbox rule (`IPAddressDeny=any`, a non-root `User=`, the sandbox set); the build unit names the failure unit in `OnFailure=`; exactly one weekly timer ships with `OnCalendar=weekly`, `Persistent=true` and a randomized delay; the rendered orchestrator configuration follows `runner-class.yml`. Bad: mutated drop-ins (allow every address, a second wider range, the whole guest subnet) and a weekly service without `IPAddressDeny=any` must be caught, so the checker is not vacuous. | **host-only proof** that the timer fires: [phase 3 index](../evidence/phase3/INDEX.md) (`evidence-timer.txt`, `evidence-timer-fired.txt`, `journal-timer-fired.txt`) |
| `test-template-content.sh` | Happy: every shipped bundle passes `lib/lint-template-content.py` and the class playbook parses. Bad: an artifact without its sha256 or sha512 pin is refused and the finding names the artifact. | none (static content rules) |
| `test-template-content-vm.sh` | Happy: the `vm-docker` class playbook passes the syntax check, `daemon.json` has no tcp host or insecure registry, every `versions.yml` entry is complete. Bad: a tcp host in `daemon.json` and a short hash in `versions.yml` are each rejected. | **host-only proof** that the daemon has no TCP listener and the clone runs a container: [phase 3 index](../evidence/phase3/INDEX.md) (`evidence-vm-clone.txt`) |

`tests/isolation/r15-probe.sh` is the probe itself, run inside a guest on the host, not a CI test; `tests/isolation/lib/fake-pve.py` and `lib/lint-template-content.py` are helpers used by the tests above.

## OpenTofu tests (`*.tftest.hcl`)

CI job: OpenTofu Lint & Validate. Local command, per stack:

```
tofu -chdir=iac/tofu/stacks/<stack> init -backend=false
TF_VAR_state_passphrase=ci-test-only-passphrase-not-a-secret-0123456789 tofu -chdir=iac/tofu/stacks/<stack> test
```

| File | Proves | Host-only proof / evidence |
|---|---|---|
| `iac/tofu/stacks/proxmox-host/tests/flavor.tftest.hcl` | Happy: every catalogue entry has positive integer sizes, balloon never exceeds memory, the `aws/t3.medium` flavor plans 2 cores, 4096 MB and 30 GB, a container has no balloon and zero swap. Bad: an unknown or malformed flavor is rejected. | none; the CI run is the proof |
| `iac/tofu/stacks/proxmox-host/tests/sdn.tftest.hcl` | Happy: the first host plans the inventory guest network and the SDN policy. Bad: a subnet overlapping management, a supernet of management, an overlap with the reserved range, a prefix longer than /28, a gateway outside the subnet are each rejected. | **host-only proof** that the zone, vnet and SNAT really exist: [phase 2 index](../evidence/phase2/INDEX.md) (`probe-tofu-apply1.txt`, `probe-tofu-apply2.txt`) |
| `iac/tofu/stacks/proxmox-host/tests/two_hosts.tftest.hcl` | Happy: the first host plans its subnet and a second host plans with no code change. Bad: an unknown host is rejected. | none |
| `iac/tofu/stacks/r15-probe/tests/policy.tftest.hcl` | Happy: clones inherit the template firewall and the stack declares none of it; guests are unprivileged, start on boot and sit on the guests vnet; addresses, DNS and ipfilter follow the guest subnet; clones come linked from the resolved templates; the VM clone installs the probe key from the vendor-data snippet. Bad: a private key and an address outside the host subnet are rejected. Edge: clones overwrite the inherited template tags; a pin changes the clone source. | **host-only proof** that clones inherit tags and the guest firewall and that an LXC update rejects `ssh-public-keys`: [phase 3 index](../evidence/phase3/INDEX.md) (`probe-tofu-apply1.txt`, `probe-tofu-apply2.txt`) |
| `iac/tofu/stacks/r15-probe/tests/template_source.tftest.hcl` | Happy: the `current` tag selects the one LXC template and the one VM template; a pin selects its version and overrides `current`. Bad (fail closed): a pin to a missing version, zero matches, two matches, `current` on a running guest, a template outside the class block, a template outside the templates pool, an unknown class, a non-whole pin. Edge: a clone outside the pool that carries the template tags is ignored. | **host-only proof** against real tags and pools: [phase 3 index](../evidence/phase3/INDEX.md) (`probe-tofu-apply1.txt`) |

## Ansible Molecule

| Scenario | Proves | Run locally | CI job | Host-only proof / evidence |
|---|---|---|---|---|
| `iac/ansible/roles/base/molecule/default` (`converge.yml`, `verify.yml`) | Happy: the `base` role converges in a Debian 13 systemd container, a second run changes nothing, and `verify.yml` asserts the effective sshd settings, the SSH service, the boot-time dead-man unit, the sudoers drop-in, the key-only automation account with its keys, the root key restriction and chrony with its sources. Bad: the revoked root key is asserted absent from root's authorized keys. | `cd iac/ansible/roles/base && molecule test` (needs Docker) | Ansible Lint, Syntax & Molecule | **host-only proof** that sshd hardening and the dead-man work on real PVE: [phase 2 index](../evidence/phase2/INDEX.md) (`converge-site-8.txt`, `host-facts.txt`) |

## Affected-graph selector harness

| File | Proves | Run locally | CI job |
|---|---|---|---|
| `tests/verify-affected-graph.sh` | Exact-set verification of the .NET transitive graph selector `scripts/apps/dotnet-affected-test.sh` in seven scenarios, with every git write inside a disposable clone. The workflow adds three mutants that must each fail a named scenario. | `./tests/verify-affected-graph.sh` | Verify Affected Graph Selector Engine |
| `tests/verify-affected-graph.ps1` | The same selector contract through the PowerShell selector in six scenarios. | `pwsh -File ./tests/verify-affected-graph.ps1` | Verify Affected Graph Selector Engine |

## Evidence publisher

| File | Proves | Run locally | CI job |
|---|---|---|---|
| `tests/evidence/test_publish.py` | Substitution is exact-value and longest first, never re-applied to a label, and never cuts a value out of a longer address or a version string. Every checker rule is red on a crafted line; allowlisted addresses stay clean; a dotted version-like token is soft only. `--check` output carries `file:line:rule` and never the matched text. The index hashes equal the bytes; an anchored file needing a substitution is withheld; a credential-mask marker or a checker flag withholds a file and fails the run. The email rule exempts systemd unit names and `.arpa` names but still flags real addresses. An address in a git-tracked file under an allowed directory is accepted, one absent from tracked files or present only under `iac/secrets/` still flags, and the allowed-address list requires a reason per line. Each of these behaviours, and the email rule itself, has a mutant that turns a named test red. | `python3 -m unittest discover -s tests/evidence -v` | Evidence Publisher Tests & Published-Text Check |

## Host-only verifiers (not run by CI)

These need the real host or the operator workstation. Their runs are the evidence.

| File | Proves | Evidence |
|---|---|---|
| `iac/ansible/playbooks/r15-verify.yml` | Creates the control key the probe guests trust (tag `r15_keygen`) and runs the R15 isolation controls from inside the probe guests | [phase 2 index](../evidence/phase2/INDEX.md), [phase 3 index](../evidence/phase3/INDEX.md) |
| `scripts/hyperv/Test-R15Controls.ps1` | Windows-side paired controls: the same target reached from the host while the guest is blocked | [phase 2 index](../evidence/phase2/INDEX.md) (`controls-after-host-reboot.txt`) |
| `iac/ansible/roles/pve_firewall/tasks/verify.yml`, `iac/ansible/roles/pve_templates/tasks/assert.yml`, `iac/ansible/roles/pve_api_identity/tasks/assert.yml` | In-role assertions that run during a converge on the host | [phase 3 index](../evidence/phase3/INDEX.md) (`converge-site-1.txt`, `converge-site-7.txt`) |
