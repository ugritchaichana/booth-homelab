# Worked examples

Eleven tasks an adopter will do, each with the exact commands and the output a real run produced. Output is quoted only from published evidence and cited as `docs/evidence/<phase>/<file>:<line>`; where no run is recorded the example says so. Evidence files keep terminal colour codes, which are left out of the quotes.

## Contents

1. [Create a guest sized by a cloud flavor](#1-create-a-guest-sized-by-a-cloud-flavor)
2. [Add a flavor to the catalog](#2-add-a-flavor-to-the-catalog)
3. [Log in to the Proxmox web interface and find things](#3-log-in-to-the-proxmox-web-interface-and-find-things)
4. [Read the build cache status from a guest](#4-read-the-build-cache-status-from-a-guest)
5. [Use the cache client in a build](#5-use-the-cache-client-in-a-build)
6. [Build a new template version and roll back](#6-build-a-new-template-version-and-roll-back)
7. [Run the R15 isolation probes and read the result](#7-run-the-r15-isolation-probes-and-read-the-result)
8. [Add a second host](#8-add-a-second-host)
9. [Publish evidence](#9-publish-evidence)
10. [Write a red-first test and record it](#10-write-a-red-first-test-and-record-it)
11. [Rotate the cache writer password](#11-rotate-the-cache-writer-password)

Conventions: commands run from the repository root in the WSL toolchain; `pve` stands for `ssh -F ~/.config/homelab/ssh_config pve01` ([runbook](../../RUNBOOK.md)).

## 1. Create a guest sized by a cloud flavor

Goal: a container and a VM whose cores, memory and disk come from `aws/t3.medium`.
Prerequisites: the operator toolchain, a reachable host, and one `current` template per class (`$pve sudo homelab-template status` exits 0). Design: [ADR 0055](../adr/0055-create-flavor-sized-guests-from-a-declarative-list-with-one-command.md).

```sh
bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo           # plan only
bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo --apply   # apply; repeats once until the plan is empty
bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template vm-docker --role demo --apply
pve="ssh -F ~/.config/homelab/ssh_config pve01"
$pve sudo pct start 9501 && $pve sudo qm start 9502                                              # guests are created stopped; plain Proxmox start commands
```

Expected output, from the recorded run:

- `docs/evidence/closeout/guest-plan-lxc.txt:1` `guest demo on pve01: aws/t3.medium, lxc-runner, slot 1` (first run, before the key became role plus class)
- `docs/evidence/closeout/guest-plan-vm.txt:1` `guest demo-vm-docker on pve01: aws/t3.medium, vm-docker, slot 2`
- `docs/evidence/closeout/guest-plan-lxc.txt:96` `hostname = "demo-lxc-runner-v6"`
- `docs/evidence/closeout/guest-plan-lxc.txt:130` `1 to add, 0 to change, 0 to destroy.`
- `docs/evidence/closeout/guest-lxc-apply2.txt:3` `Apply complete! Resources: 0 added, 1 changed, 0 destroyed.` (the disk grows to 30 GB on the second apply)
- `docs/evidence/closeout/guest-settled.txt:4` `No changes. Your infrastructure matches the configuration.`
- `docs/evidence/closeout/guest-start-guard.txt:9` `guest-firewall-guard: ok, 9 guest(s) checked on pve01`

What to check: the name is `<role>-<class>-v<N>`, where `N` is the template version actually cloned; the tags are `flavor-guest`, `flavor-<provider>-<instance>` (lowercase, `/` becomes `-`) and `src-<class>-v<N>`:

- `docs/evidence/closeout/guest-plan-lxc.txt:61` `"flavor-aws-t3.medium",`
- `docs/evidence/closeout/guest-plan-lxc.txt:63` `"src-lxc-runner-v6",`

In the Proxmox interface the tree shows the tags beside each guest, so searching `flavor-aws-t3.medium` lists every guest of that size (the exact search box is HYPOTHESIS; the tag text is CONFIRMED above). A bad flavor or class exits 1 with one line and leaves `iac/tofu/stacks/guest/guests.yml` unchanged (`scripts/iac/new-guest.sh:66`).

## 2. Add a flavor to the catalog

Goal: make `<provider>/<instance>` a valid size for `new-guest.sh`.
Prerequisites: OpenTofu in the toolchain; a pull request, because the catalog resizes every guest of that flavor at its next apply ([ADR 0017](../adr/0017-size-templates-by-generic-cloud-flavors.md)).

Add one line inside `providers.<provider>.instances` of `iac/tofu/flavors.json`. The real entry it follows:

- `iac/tofu/flavors.json:11` `"t3.medium": { "cores": 2, "memory_mb": 4096, "disk_gb": 30, "balloon_mb": 2048, "description": "Burstable medium (Standard CI Runner)" },`

```sh
# new line, same shape (example values): "m5.xlarge": { "cores": 4, "memory_mb": 16384, "disk_gb": 80, "balloon_mb": 8192, "description": "General purpose xlarge" }
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123
tofu -chdir=iac/tofu/stacks/proxmox-host init -backend=false
tofu -chdir=iac/tofu/stacks/proxmox-host test
```

The guard is `iac/tofu/stacks/proxmox-host/tests/flavor.tftest.hcl`: every entry needs integer `cores`, `memory_mb` and `disk_gb`, and `balloon_mb` may not exceed `memory_mb`. Its run names are:

- `iac/tofu/stacks/proxmox-host/tests/flavor.tftest.hcl:1` `run "every_catalog_entry_has_positive_integer_sizes" {`
- `iac/tofu/stacks/proxmox-host/tests/flavor.tftest.hcl:42` `run "catalog_balloon_never_exceeds_memory" {`

Expected output: No recorded run yet for this stack's test on the host (it runs in `iac-ci.yml`, no host needed). The nearest recorded run is the guest stack's: `docs/evidence/closeout/guest-settled.txt:6` `25 passed, 0 failed.`
What to check: the test run ends with zero failures, then `new-guest.sh --flavor <provider>/<instance> ...` plans with the new size. A disk below the template disk (8 GB container, 20 GB VM) fails the plan, so `aws/t3.nano` fits only `lxc-runner`.

## 3. Log in to the Proxmox web interface and find things

Goal: open the interface and locate the objects this platform creates.
Prerequisites: the workstation that holds the age identity. The port admits only the Windows host address, so use that machine; from a tailnet device use the forward in [ADR 0008](../adr/0008-keep-proxmox-off-the-tailnet-and-reach-the-ui-through-the-host.md).

```sh
sops decrypt --extract '["root_password"]' iac/secrets/hosts/pve01.sops.yaml   # run in your own terminal; never paste the value into chat or a ticket
# browser: https://10.99.0.2:8006   user root   realm Linux PAM
```

The certificate is the host's own, so the browser warns once ([ADR 0029](../adr/0029-reach-the-proxmox-api-through-an-ssh-forward-and-skip-tls-verification-inside-it.md)). A tour:

| Where | What you see | Evidence |
|---|---|---|
| Node summary | `pve-manager` 9.2.21 | `docs/evidence/phase2/host-facts.txt:3` `pve-manager: 9.2.21 (running version: 9.2.21/4f6e0ac86f9e8c7f)` |
| Templates | `tmpl-<class>-v<N>`, stopped | `docs/evidence/closeout/rename-final-state.txt:12` `tmpl-lxc-runner-v6` |
| Datacenter, SDN | zone `hlab`, vnet `guests` 10.99.16.0/24, vnet `cache` 10.99.17.0/24 | `docs/evidence/phase4/tofu-proxmox-host-apply1.txt:5` `id=hlab`; `:8` `hlab-10.99.16.0-24`; `:53` `hlab-10.99.17.0-24` |
| Firewall, Security Group | `guest-egress` and `cache-ingress` | `docs/evidence/phase4/fw-after-sdn.txt:1` `[group guest-egress]`; `:6` `[group cache-ingress]` |
| Guests | cache container | `docs/evidence/closeout/rename-final-state.txt:10` `build-cache-debian-13` |
| Guests | probe container, probe VM | `docs/evidence/closeout/rename-final-state.txt:11` `r15-probe-lxc-runner-v6`; `docs/evidence/closeout/rename-final-state.txt:16` `r15-probe-vm-docker-v7` |
| Guests | demo container, demo VM | `docs/evidence/closeout/rename-final-state.txt:14` `demo-lxc-runner-v6`; `docs/evidence/closeout/rename-final-state.txt:19` `demo-vm-docker-v7` |

What to check: node `pve01`, every guest tagged as in example 1, and `homelab-guest-firewall-guard.service` reports `ok`. Set TOTP on `root@pam` before regular remote use (ADR 0008).

## 4. Read the build cache status from a guest

Goal: confirm the cache answers and see how many entries it holds.
Prerequisites: a shell on the node and a running probe container (VMID 9101). The cache accepts port 8080 only from the `guests` vnet, so a laptop browser cannot reach it, by design.

```sh
$pve sudo pct exec 9101 -- curl -s http://10.99.17.10:8080/status
```

Expected output, from the recorded run:

- `docs/evidence/closeout/rename-final-state.txt:6` `"NumFiles": 7,`
- `docs/evidence/closeout/rename-final-state.txt:7` `"GitTags": "v2.6.2",`

Why a laptop fails: the cache group admits only the guest subnet, and the probes record the path as open from a guest.

- `docs/evidence/phase4/fw-after-sdn.txt:7` `IN ACCEPT -source 10.99.16.0/24 -p tcp -dport 8080`
- `docs/evidence/phase4/r15-baseline-lxc.txt:23` `PROBE cache_port_reachable tcp 10.99.17.10:8080 open open PASS`

What to check: valid JSON with `NumFiles` above 0 after a default-branch build has saved. The pipeline makes the same call in its telemetry step (`.github/workflows/reusable-sdet-pipeline.yml:119`). No published file holds the full `/status` body; only the two lines above were kept.

## 5. Use the cache client in a build

Goal: restore, save and report build caches through `scripts/ci/build_cache/`.
Prerequisites: Python 3.11 or newer; `CACHE_URL` set. A save needs a push to the default branch plus `CACHE_WRITER_PASSWORD` (`scripts/ci/build_cache/domain/policy.py:13`); anything else restores only. No status fails a job ([runbook 3.4](../../RUNBOOK.md)).

Subcommands (`scripts/ci/build_cache/cli.py`): `restore`, `save`, `report`. Kinds: `nuget`, `node_modules`, `dotnet-outputs`. The workflow wraps the first two in `./.github/actions/build-cache` with `mode` and `kind`.

```sh
export PYTHONPATH=scripts/ci CACHE_URL=http://10.99.17.10:8080
stats="$RUNNER_TEMP/build-cache-stats.jsonl"
python3 -m build_cache restore --kind nuget --root . --stats-file "$stats"
CACHE_WRITER_PASSWORD=<the CI secret> python3 -m build_cache save --kind nuget --root . --stats-file "$stats"   --event push --ref refs/heads/main --default-branch main                                      # writer context only
python3 -m build_cache report --stats-file "$stats"
```

Expected output, a miss and save in run 1, hits in run 2:

- `docs/evidence/phase4/cache-loop20-results.txt:2` `iter=1 op=restore kind=nuget status=miss bytes=0 ms=1`
- `docs/evidence/phase4/cache-loop20-results.txt:5` `iter=1 op=save kind=nuget status=saved bytes=71792850 ms=2972`
- `docs/evidence/phase4/cache-loop20-results.txt:9` `iter=2 op=restore kind=nuget status=hit bytes=71792850 ms=2646`
- `docs/evidence/phase4/cache-loop20-results.txt:12` `iter=2 op=save kind=nuget status=skipped bytes=0 ms=0`

What to check: the effect on wall time. Summing `restore_deps_ms`, `install_ms`, `restore_outputs_ms` and `build_ms` on `:1` gives 12.9 s for the cold run; the median of runs 2 to 20 is 9.8 s. Only one cold run exists, so treat the gap as indicative. Both figures are sums over the columns named, not lines in the file.

## 6. Build a new template version and roll back

Goal: produce template `v<N+1>` of a class, then undo its promotion.
Prerequisites: root on the host through `$pve sudo`; no probe run or runner job in flight ([runbook 3.3](../../RUNBOOK.md)). Design: [ADR 0040](../adr/0040-version-templates-with-a-monotonic-number-a-root-only-current-tag-and-automatic-promotion.md).

```sh
$pve sudo systemctl start --no-block homelab-template-build@lxc-runner.service
$pve sudo journalctl -f -u homelab-template-build@lxc-runner.service
$pve sudo homelab-template status
$pve sudo homelab-template rollback lxc-runner     # current and previous swap; run again to swap back
bash scripts/iac/new-guest.sh --flavor aws/t3.medium --template lxc-runner --role demo --version v5 --apply   # pin one guest (the clone source changes, so the guest is replaced)
```

Expected output, a timer-fired rebuild of `lxc-runner` and a rollback:

- `docs/evidence/phase3/journal-timer-fired.txt:5` `PREFLIGHT ok data_percent=20.06 metadata_percent=2.01 local_free_gib=32.5`
- `docs/evidence/phase3/journal-timer-fired.txt:6` `BUILD start class=lxc-runner version=v6 vmid=9202`
- `docs/evidence/phase3/journal-timer-fired.txt:26` `VERIFY ok clone=9201 is a linked clone of 9202 (origin vm-9201-disk-0)`
- `docs/evidence/phase3/journal-timer-fired.txt:32` `PROMOTED class=lxc-runner v5 -> v6 vmid=9202`
- `docs/evidence/phase3/journal-timer-fired.txt:35` `RETENTION destroyed vmid=9203 v4`
- `docs/evidence/phase3/proof-rollback-token.txt:5` `ROLLBACK class=lxc-runner current v4 -> v3 previous=v4 vmid=9202`
- `docs/evidence/phase3/proof-rollback-token.txt:11` `ROLLBACK class=lxc-runner current v3 -> v4 previous=v3 vmid=9203`

What to check: `status` exits 0 with one `current` per class. A failed build ends in `FAILED` or `REFUSED`. Rollback moves `current` for every consumer; a `--version` pin moves one guest and needs no host access. The first recorded build failed on a permission error and is kept as the defect record, not as a model run: `docs/evidence/phase3/build-weekly-1.txt:27`

## 7. Run the R15 isolation probes and read the result

Goal: prove runner-class guests cannot reach management, other guests or private networks.
Prerequisites: [runbook 2.8](../../RUNBOOK.md) steps 1 to 4 done (controls, key, probe clones); read the file the run writes, never the terminal.

```sh
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=red-first -e r15_output_dir=<results directory>   # attended: stops the node firewall
bash scripts/iac/ansible.sh r15-verify.yml -l pve01 -e r15_phase=baseline -e r15_output_dir=<results directory>
```

Expected output, container probe with the cache path:

- `docs/evidence/phase4/r15-red-first-lxc.txt:3` `PROBE gateway_ssh tcp 10.99.16.1:22 open open PASS`
- `docs/evidence/phase4/r15-baseline-lxc.txt:3` `PROBE gateway_ssh tcp 10.99.16.1:22 blocked dropped PASS`
- `docs/evidence/phase4/r15-baseline-lxc.txt:19` `NOT MEASURED`
- `docs/evidence/phase4/r15-baseline-lxc.txt:26` `SUMMARY negatives_blocked=19/19 positives_ok=2/2 egress_curl=200`
- `docs/evidence/phase4/r15-baseline-cache.txt:18` `SUMMARY negatives_blocked=12/12 positives_ok=1/1 egress_curl=200`

What to check: the same target reads open in `red-first` and blocked in `baseline`, which shows the filter did the blocking; `SUMMARY` has every measured negative blocked and `EXIT 0`. A `NOT MEASURED` row has no positive control and is not counted. Field meaning: `tests/isolation/README.md`.

## 8. Add a second host

Goal: plan and apply the stacks for a host named `pve02`.
Prerequisites: a Proxmox host the roles support, with its own address ranges. Evidence level: planned only, never applied ([operations](operations.md)).

The first inventory entry, verbatim from `iac/inventory/hosts.yml:6-24`:

```yaml
        pve01:
          ansible_host: 10.99.0.2
          ansible_user: automation
          ansible_ssh_pipelining: true
          ssh_key_name: homelab_pve01_ed25519
          pve_node_name: pve01
          management_source: 10.99.0.1
          guest_network:
            zone: hlab
            vnet: guests
            cidr: 10.99.16.0/24
            gateway: 10.99.16.1
          cache_network:
            vnet: cache
            cidr: 10.99.17.0/24
            gateway: 10.99.17.1
          cache_endpoint:
            address: 10.99.17.10
            port: 8080
```

The second entry sits beside it under `pve_hosts.hosts` with the same keys and its own values. Example values (the test fixture reuses 10.99.17.0/24, so it is not a model for real ranges):

```yaml
        pve02: {ansible_host: 192.0.2.20, ansible_user: automation, ssh_key_name: homelab_pve02_ed25519, pve_node_name: pve02, management_source: 192.0.2.5}
        # guest_network: cidr 10.99.20.0/24, gateway 10.99.20.1; cache_network and cache_endpoint on ranges no other host uses
```

```sh
sops iac/secrets/hosts/pve02-ssh.sops.yaml              # ssh_host_ed25519_public; the SSH config render fails without it
bash scripts/iac/render-ssh-config.sh
bash scripts/iac/tofu.sh proxmox-host pve02 init-passphrase
bash scripts/iac/tofu.sh proxmox-host pve02 plan
bash scripts/iac/new-guest.sh --flavor aws/t3.small --template lxc-runner --role ci --host pve02   # --host is required once two hosts exist
```

Expected output: No recorded run yet. The offline proof is the fixture test, `iac/tofu/stacks/proxmox-host/tests/fixtures/hosts.yml` plus:

- `iac/tofu/stacks/proxmox-host/tests/two_hosts.tftest.hcl:20` `run "second_host_plans_with_no_code_change" {`

What to check: the plan names `pve02`, its own subnet and gateway; each host has its own state file and its own template builds and cache ([porting](porting.md)). The cache play reads `iac/inventory/cache.yml`, whose host takes its address from `pve01`; give `pve02` its own cache entry there before running it.

## 9. Publish evidence

Goal: turn raw host transcripts into sanitized files under `docs/evidence/<phase>/` with an index.
Prerequisites: Python 3.11 or newer, a value map and a credential mask script kept outside the repository ([runbook 4.3](../../RUNBOOK.md); [ADR 0052](../adr/0052-publish-sanitized-evidence-and-knowledge-in-the-repository.md)).

The map is JSON with a `pairs` list of exact value and label. Three FAKE pairs:

```json
{"pairs": [["203.0.113.10", "<host-lan>"],
           ["example-box", "<tailnet-node-0>"],
           ["/home/operator", "<user-home>"]]}
```

One real selection entry, from `scripts/evidence/selection-closeout.json:54-58` (the raw folder name is shortened here):

```json
    {
      "src": "plans:<project folder>/raw/rename-plan.txt",
      "dest": "docs/evidence/closeout/rename-plan.txt",
      "proves": "Guest names: plans before the rename, in place only (r15-probe 2 to change, cache-service 1 to change)"
    },
```

```sh
python3 scripts/evidence/publish.py --repo . --allow-addresses-from iac --map /work/map.json --mask-script /work/mask.py \
  --raw-root plans=/work/plans scripts/evidence/selection-closeout.json
python3 scripts/evidence/publish.py --check docs/evidence docs/knowledge --allow-addresses-from iac
```

Expected output, printed to stderr (the format is `scripts/evidence/publish.py:428`; no published file captures the line; the run is described in the commit message of the publishing commit):

```text
closeout: published=15 withheld=0 substitutions={'user-home': 2}
```

- `docs/evidence/closeout/INDEX.md:10` `user-home: 2`

What to check: `withheld=0` and exit 0 on both commands. A withheld file is never edited by hand: read its `file:line:rule` output, add the exact value to the map, run again. `--check` prints positions, never the matched text.

## 10. Write a red-first test and record it

Goal: prove a test can fail before trusting its green.
Prerequisites: the repository checkout; work on a copy so production files stay untouched.

The pattern: break the production file in a scratch copy, see the test go red, restore by discarding the copy. `tests/cache/test_dependency_rule.py` builds the scratch copy itself (`mutated_copy`, `assert_mutation`) and checks that the layer rule catches each break. By hand:

```sh
bash -c 'cd "$(mktemp -d)" && mkdir -p scripts tests && cp -r "$OLDPWD/scripts/ci" scripts/ci && cp -r "$OLDPWD/tests/cache" tests/cache \
  && echo "import os" >> scripts/ci/build_cache/domain/keys.py \
  && PYTHONPATH=scripts/ci python3 -m unittest discover -s tests/cache -p "test_dependency_rule.py"'
PYTHONPATH=scripts/ci python3 -m unittest discover -s tests/cache -p "test_dependency_rule.py"   # real tree: green
```

The same pattern for a shell test: `tests/isolation/test-role-hyperv-guest.sh` reads `HYPERV_GUEST_ROLE_DIR`, so point it at a scratch copy of `iac/ansible/roles/hyperv_guest` with an assertion deleted. It prints `FAIL: ...` lines and exits 1 (`tests/isolation/lib/role-fakes.sh:65`, `:75`).

Expected output: No recorded run yet. Measured locally while writing this page, not published: the first run fails `test_layers_only_point_inward`, naming `domain/keys.py imports I/O module os`, and the test that expects a clean tree after its own mutation; the second run ends `OK`.
Where it is recorded: one row per test file in the catalogue:

- `docs/knowledge/test-catalogue.md:91` `tests/cache/test_dependency_rule.py`

What to check: the red run fails for the reason you broke, not for another one, then the restored tree is green. A shell test gets a row in the `tests/isolation/` table, which `test-role-hyperv-guest.sh` does not have yet: `docs/knowledge/test-catalogue.md:22`

## 11. Rotate the cache writer password

Goal: replace the one credential that may write to the cache, in the encrypted file and in the GitHub environment secret.
Prerequisites: the age identity, `sops` and `gh` signed in with admin rights on the repository, the environment `cache-writer` present. `scripts/iac/cache-writer-secret.sh` generates 48 characters, writes them through stdin, and never prints them.

```sh
bash scripts/iac/cache-writer-secret.sh --rotate --repo <owner>/<repository>
bash scripts/iac/ansible.sh iac/ansible/playbooks/cache.yml -i iac/inventory/hosts.yml -i iac/inventory/cache.yml
```

Without `--rotate` the script only reports that the secret exists. If the GitHub step fails the file is already updated; run again with `--rotate`.

Expected output: No recorded run yet of a rotation on the host (script tested offline with stubs: `tests/isolation/test-cache-writer-secret.sh`). The recorded shape of a cache converge that ends with nothing to change:

- `docs/evidence/closeout/rename-ssh-converge.txt:12` `build-cache                : ok=22   changed=0    unreachable=0    failed=0`

After a real rotation the converge should show the cache unit restarted (`changed` above 0, HYPOTHESIS). What to check: a default-branch build saves (`status=saved`), an anonymous write returns 401 and a pull-request build still restores. Schedule a drill and record it ([operations](operations.md)).
