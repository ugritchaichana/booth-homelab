# 07. Infrastructure as Code (OpenTofu and Ansible)

The Proxmox host and its guests are managed by declarative code (ADR 0012). The decisions behind each part are in `docs/adr/`; this page maps the layout.

| Path | Purpose | Decision |
| :--- | :--- | :--- |
| `iac/inventory/hosts.yml` | The single host data file read by Ansible and OpenTofu, with `group_vars/` and `host_vars/` beside it; `cache.yml` adds the cache container | ADR 0021 |
| `iac/ansible/` | Playbooks `bootstrap.yml`, `site.yml`, `cache.yml`, `r15-verify.yml`; roles `base`, `hyperv_guest`, `pve_host`, `pve_api_identity`, `pve_firewall`, `pve_templates`, `cache_service` | ADR 0023 to 0027, 0038, 0048 |
| `iac/tofu/stacks/proxmox-host/` | Root module for every host in the inventory: SDN zone and the `guests` and `cache` vnets | ADR 0013, 0029, 0030, 0045 |
| `iac/tofu/stacks/cache-service/` | The cache container `cache01` | ADR 0045, 0048 |
| `iac/tofu/stacks/r15-probe/` | Throwaway probe guests, cloned from the golden templates, for the isolation proof | ADR 0031, 0032, 0044 |
| `iac/tofu/modules/` | `proxmox/sdn`, `proxmox/template-source`, `flavor` | ADR 0017, 0030, 0044 |
| `iac/policy/runner-class.yml` | Per-guest firewall policy of the runner class | ADR 0027, 0044 |
| `iac/secrets/` | SOPS-encrypted host and OpenTofu secrets, one file per consumer and host | ADR 0009, 0033 |
| `scripts/iac/` | Wrappers `ansible.sh`, `tofu.sh`, `render-ssh-config.sh`, `cache-writer-secret.sh` | ADR 0011, 0022, 0050 |
| `scripts/bootstrap/operator-toolchain.sh` | Installs the pinned, hash-verified operator tools in WSL | ADR 0010 |

The bootstrap scripts, cache policies and Ansible content of the previous host were retired instead of ported (ADR 0020).

## Who owns what

Ansible owns OS configuration, sshd, the host and cluster firewall files, the OpenTofu API identity, base images, snippets, the template build framework and the cache service. OpenTofu owns SDN, guests, guest firewall options and the template lookup. Storage definitions stay as the installer made them (ADR 0025, 0035).

## Instance flavor catalog

`iac/tofu/flavors.json` maps public cloud instance tiers (AWS, GCP, Azure, Hetzner, DigitalOcean) to Proxmox sizes, so templates and guests are sized by a generic flavor name instead of hardcoded CPU and memory (ADR 0017). A test asserts every entry has positive `cores`, `memory_mb` and `disk_gb`, and that `aws/t3.medium` plans 2 cores, 4096 MB and 30 GB (row 60).

## OpenTofu workflow

Run every stack through the wrapper. It opens the SSH forward to the Proxmox API, decrypts secrets into the `tofu` process only, and keeps encrypted state on the WSL filesystem, one state per stack and host (ADR 0013, 0051):

```bash
bash scripts/iac/tofu.sh proxmox-host pve01 init-passphrase   # once
bash scripts/iac/tofu.sh proxmox-host pve01 init
bash scripts/iac/tofu.sh proxmox-host pve01 plan
bash scripts/iac/tofu.sh proxmox-host pve01 apply
```

After an apply, `plan -detailed-exitcode` must return 0 (row 49). Checks that need no host: `iac/tofu/README.md`.

## Ansible workflow

```bash
bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root   # first contact, the only play that connects as root
bash scripts/iac/ansible.sh site.yml                              # steady state, as the automation user
```

`scripts/iac/ansible.sh` renders the SSH config from the inventory when it is missing and pins the host key (ADR 0022). A second `site.yml` run must report `changed=0` (rows 43, 46). Static checks and the Molecule scenario for the `base` role: `iac/ansible/README.md` (ADR 0024).

## Identity and least privilege

The OpenTofu token is created by Ansible, not by OpenTofu, and its secret goes straight into SOPS (ADR 0026). It is split into seven purpose roles, each granted only on its path, and it cannot create users, change the host or delete a template (row 48, 57).
