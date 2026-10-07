# 07. Infrastructure as Code (OpenTofu & Ansible)

## 1. Overview & Architecture

The **Booth-homelab** Proxmox host is managed through declarative Infrastructure-as-Code and configuration management (ADR 0012). The decisions behind each part are recorded in `docs/adr/`; this page only maps the layout.

| Path | Purpose | Decision |
| :--- | :--- | :--- |
| `iac/inventory/hosts.yml` | The single host data file read by Ansible and OpenTofu, with `group_vars/` and `host_vars/` beside it. | ADR 0021 |
| `iac/ansible/` | Playbooks `bootstrap.yml`, `site.yml` and `r15-verify.yml`; roles `base`, `hyperv_guest`, `pve_host`, `pve_api_identity`, `pve_firewall`. | ADR 0023, 0024, 0025, 0026 |
| `iac/tofu/stacks/proxmox-host/` | Root module for every host in the inventory; local, encrypted state. | ADR 0013, 0029 |
| `iac/tofu/stacks/r15-probe/` | Throwaway probe guests for the guest isolation proof. | ADR 0031, 0032 |
| `iac/tofu/modules/proxmox/sdn/` | Guest network: simple SDN zone, vnet and subnet. | ADR 0030 |
| `iac/tofu/modules/flavor/` | Resolves a flavor name to cores, memory and disk, with ready VM and container size objects. | ADR 0017 |
| `iac/tofu/flavors.json` | Instance flavor catalog read by `modules/flavor/`. | ADR 0017 |
| `iac/secrets/` | SOPS-encrypted host and OpenTofu secrets. | ADR 0009 |
| `scripts/iac/` | Wrappers `render-ssh-config.sh`, `ansible.sh` and `tofu.sh`. | ADR 0011, 0022 |

The bootstrap scripts, cache policies and Ansible content of the previous host were retired instead of ported (ADR 0020).

---

## 2. Instance Flavor Catalog

`iac/tofu/flavors.json` maps public cloud instance tiers (AWS, GCP, Azure, Hetzner, DigitalOcean) to Proxmox VE hardware sizes, so templates are sized by a generic flavor name rather than hardcoded CPU and memory (ADR 0017). The file is the source for the supported tiers.

---

## 3. OpenTofu Provisioning Workflow

Run every stack through the wrapper, which opens the SSH forward to the Proxmox API, decrypts the secrets into the `tofu` process only and keeps the encrypted state outside the repository (details in `iac/tofu/stacks/proxmox-host/README.md`):

```bash
bash scripts/iac/tofu.sh proxmox-host pve01 init-passphrase   # once
bash scripts/iac/tofu.sh proxmox-host pve01 init
bash scripts/iac/tofu.sh proxmox-host pve01 plan
bash scripts/iac/tofu.sh proxmox-host pve01 apply
```

Checks that need no host are listed in `iac/tofu/README.md`.

---

## 4. Ansible Configuration Management Workflow

```bash
# First contact, as root (the only play that connects as root)
bash scripts/iac/ansible.sh bootstrap.yml -e ansible_user=root

# Steady state, as the automation user
bash scripts/iac/ansible.sh site.yml
```

`scripts/iac/ansible.sh` renders the SSH config from the inventory when it is missing and pins the host key (ADR 0022). Static checks and the Molecule scenario for the `base` role are described in `iac/ansible/README.md` (ADR 0024).
