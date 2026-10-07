# 0038. Build golden templates with a root orchestrator, a sandboxed guest-facing step and in-guest Ansible

- Status: Accepted
- Date: 2026-10-07
- Deciders: operator
- Decision log: D66 in docs/platform/requirements.md

## Context

Phase 3 needs golden templates for the runner classes, rebuilt on a schedule and tagged with a version and a manifest. A build is several steps in order: create a guest, start it, configure its operating system, clean it, stop it, convert it, verify a clone. ADR 0012 lists "templates" in the OpenTofu column and everything inside an operating system in the Ansible column.

Facts that decide the path:

- A plan cannot express "boot, wait, run Ansible, shut down, convert". The provisioning step would live outside the plan whatever the tool.
- The scheduled rebuild runs on the Proxmox host. Running OpenTofu there would put the state passphrase, the SOPS age key and an API token on the host (ADR 0013, ADR 0033).
- Deleting a volume through the API needs `Datastore.Allocate`, which ADR 0026 and ADR 0035 withhold from the provisioner token, so retention runs as host root under every option.
- The build guest runs third-party maintainer scripts. A root process on the host that parses what a hostile guest sends back (Ansible module results, fetched files, SSH messages) turns a compromised package into host root, and the host routes the operator's private prefixes (ADR 0027).
- The probe already established the channel: SSH from the host with a key that never leaves it, one inbound rule from the gateway (ADR 0032).

## Options considered

1. OpenTofu creates the build guest and the template, Ansible runs from the operator machine — follows ADR 0012 literally, but cannot run from a timer on the host without the secrets above, and still needs a script for boot, provision and convert.
2. Packer — a new tool, no container builder found, and no model of retention or rollback; ADR 0012 admits extra tools only with a recorded reason.
3. A host-side root script that runs `ansible-playbook` over SSH into the build guest — one tool chain, but root parses hostile output.
4. A host-side root orchestrator that issues only host-chosen `qm`, `pct`, `pvesh` and `lvs` commands, hands the one guest-facing step to a non-root user in a sandboxed unit, and runs Ansible inside the guest with `-c local`.

## Decision

Option 4. `iac/ansible/roles/pve_templates` installs, on the Proxmox host:

- `/usr/local/sbin/homelab-template` (root): `build <class>`, `rollback <class>`, `status [class]`, `repair <class>` and `record-failure <class>`. Nothing here parses a byte from a guest. It runs `qm`, `pct`, `pvesh` and `lvs` with arguments it chose, plus `ssh-keygen` (the ephemeral key), `systemctl start --wait` (the unit hand-off) and `logger` (journal lines when run outside a unit, composed from host-side tool output, never from guest bytes). It may sha256 the opaque manifest and compare a pass marker byte for byte with a string it expects.
- A system user `homelab-tmpl` and the unit `homelab-template-guest@.service` (`build` and `verify` instances). The unit runs as that user with `IPAddressDeny=any` and `IPAddressAllow=<guest subnet>` (a drop-in rendered from the inventory), `ProtectSystem=strict`, `ProtectHome=yes`, `InaccessiblePaths=/etc/pve /root`, `NoNewPrivileges=yes`, an empty capability set and no `~/.ssh`. The step is the only code that touches guest bytes: SSH with `BatchMode=yes`, `IdentitiesOnly=yes`, `ForwardAgent=no`, `ForwardX11=no`, `ClearAllForwardings=yes`, `PermitLocalCommand=no`, `-F /dev/null` and a per-build `UserKnownHostsFile`; it pushes a content bundle, runs the bundle's `run.sh` inside the guest, fetches the pass marker and one size-capped manifest, parses the manifest as JSON, prints the manifest diff against the previous version to its own journal, seals the guest, and writes `out/pass` only when the marker carries this build id and the seal succeeded. `ExecStopPost=` deletes the key and known_hosts; the orchestrator also deletes the whole work directory.
- A root-owned state directory (`/var/lib/homelab/templates`, mode 0700) holding per-class state, stored manifests and failure markers; a root-owned configuration rendered from role variables and `iac/policy/runner-class.yml`.
- `homelab-template-build@.service` (root) with `OnFailure=homelab-template-failure@%i.service`, which writes a critical journal line and a marker file. No timer ships here; the scheduled rebuild is a later change.

The build, in order: lock (one build at a time); destroy leftover non-template guests in the class block; refuse above the thin-pool and storage thresholds (ADR 0039); create the build guest in no pool, with its only NIC on the guest vnet, the runner-class firewall options, the `guest-egress` group rule, one inbound tcp/22 rule from the gateway, an `ipfilter-net0` set for a VM, an unprivileged container with no mount point, raw `lxc.*` key or `features`, and a VM with the guest agent off, no `hostpci`, `usb`, `virtiofs`, `serial` or `args`, and the pinned CPU model; read every one of those attributes back and fail on any difference, journaled before the first start; start; run the guest unit; require the pass marker for this build id; stop; delete the inbound rule, the key, the build address, `ipconfig*`, `cicustom` and the cloud-init user from the config; read the template back; convert; add to pool `templates`; set the tags; verify a linked clone (ADR 0039); promote (ADR 0040).

The bundle contract: the role installs a common bundle under `/usr/local/share/homelab-template/common` (`run.sh`, a minimal `playbook.yml`, `finalize.sh`, `seal.sh`, an allowlist for the scan). A class bundle is a directory of files copied over the common ones, normally its own `playbook.yml`. `run.sh <build id>` installs `ansible-core` in the guest when it is missing, runs `ansible-playbook -c local -i localhost, playbook.yml` inside the guest, which writes `/var/lib/homelab-build/manifest.json`, purges the Ansible it installed, and ends by calling `finalize.sh <build id>`. `finalize.sh` cleans the guest (machine-id truncated, random seed, logs, shell history, Ansible temporary files), scans for forbidden files, key material, runner credentials and token patterns with an allowlist keyed by path and sha256, and only then writes `/var/lib/homelab-build/pass`. A failed scan means no marker, no conversion and a destroyed guest.

The channel closes last. The finalize step leaves the login user's `authorized_keys` and the SSH host keys alone, because the guest step still has to open two connections to fetch the marker and the manifest. After both fetches, `seal.sh` is the last connection: it removes the login keys and host keys, truncates `machine-id` again, removes the build output and the pushed bundle, verifies none is left, disables `ssh.service` and `ssh.socket` and prints `SEAL-OK`. The guest step writes `out/pass` only when `SEAL-OK` is on the output, whatever the exit status of the closing connection. The root orchestrator then deletes the inbound rule before conversion, so a template carries no way in.

This amends the "templates" row of ADR 0012: building a template belongs to this path, OpenTofu keeps consuming templates (cloning). ADR 0012 allows an imperative script only as a thin wrapper over one of the two tools: the in-guest half stays Ansible, and the Proxmox-API half is this orchestrator because only host root can delete volumes and run the conversion sequence above.

## Rationale and trade-offs

- Nothing hostile reaches root. The one parser of guest bytes (JSON, size-capped) runs as a user that cannot read `/etc/pve` or `/root`, reach any address outside the guest subnet, or gain privileges. The manifest diff is printed by that user, not by root.
- `ssh-keygen`, `systemctl` and `logger` are outside the commands first proposed for root (`qm`, `pct`, `pvesh`, `lvs`); none takes guest bytes. The key must exist before the first start because the guest receives it at create time.
- No builder API token: on the same host as root it adds no containment.
- Accepted: Ansible and its dependencies are installed in every build guest and removed by the cleanup, which costs build time (not measured).
- Accepted: the verification in this change is structural and host-side (ADR 0039). An in-guest check of a clone (R15 baseline, `docker run hello-world`) needs a started clone with its own channel; the unit's `verify` instance and the per-class hook path are the slot for it, and the class changes fill it. Until then the in-guest checks run in the build guest, before conversion.
- Accepted: a failed build destroys its guest, so its evidence is the journal, not the guest.
- HYPOTHESES, settled only by the host proof: that `qm set` edits tags and the description of a template; that `qm create --import-from`, `qm resize` and `pct create --ssh-public-keys` take the arguments used here on PVE 9.2; that `pvesh get .../firewall/options` returns every option explicitly (the read-back fails closed if one is missing); that the sandbox directives load on the host; that `ssh.service` and `ssh.socket` are the unit names in both guest images and stay disabled in the template; and whether a clone inherits the guest firewall file (the stripped template is what bounds it).
- Offline tests (`tests/isolation/test-template-build.sh`, `test-template-guest-step.sh`, `test-template-finalize.sh`, `test-template-units.sh`) run the real scripts against fakes for `pvesh`, `qm`, `pct`, `lvs`, `systemctl` and `ssh`. They prove the logic and the unit file, not the behaviour of Proxmox.
