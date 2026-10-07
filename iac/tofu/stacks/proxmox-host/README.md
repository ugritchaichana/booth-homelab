# proxmox-host stack

One root module for every Proxmox host in `iac/inventory/hosts.yml`. `var.host` selects the entry, so a new host is an inventory row, not new code. The guest network comes from `modules/proxmox/sdn` (ADR 0030): the vnet `guests` and, when the entry has `cache_network`, the vnet `cache` (ADR 0045).

## Run

Always through the wrapper, which opens the SSH forward, decrypts the secrets into the `tofu` process only, and keeps state on the WSL ext4 filesystem:

```sh
bash scripts/iac/tofu.sh proxmox-host pve01 init-passphrase     # once; --rotate replaces it
bash scripts/iac/tofu.sh proxmox-host pve01 init
bash scripts/iac/tofu.sh proxmox-host pve01 plan
bash scripts/iac/tofu.sh proxmox-host pve01 apply
```

One-time setup of the state root: `sudo install -d -o "$USER" -m 0700 /var/lib/homelab/tofu`.

`apply` and `destroy` first run `sudo -n ifquery --check -a` on the host as `automation`, over the rendered ssh config, and refuses when it returns non-zero, printing its output. The SDN applier runs on both and reloads the whole network config, so drift between `/etc/network/interfaces` and the running state would be applied together with the guest bridge. `plan` skips the check.

## Verify after apply

Read-only, on the host as `automation` (`ssh pve01`). Each must hold before any guest is attached:

```sh
bridge -d link show | grep -A1 'master guests'        # every guest port: isolated on (empty until a guest exists)
sudo iptables -t nat -S POSTROUTING | grep 10.99.16.0/24   # the SNAT rule for the guest subnet
sysctl -n net.ipv4.ip_forward                         # 1
ip -4 -o addr show guests                             # exactly the gateway, 10.99.16.1
cat /proc/sys/net/ipv4/conf/cache/forwarding          # 1, when the cache vnet is declared
sudo iptables -t nat -S POSTROUTING | grep 10.99.17.0/24   # SNAT out of vmbr0 only
```

The SNAT and isolation lines are the only proof that `isolate_ports` and `snat` took effect on the kernel; the plan only shows the API objects (ADR 0030). A second apply must end with `plan -detailed-exitcode` returning 0.

## Where things live

| Item | Location |
|---|---|
| State | `/var/lib/homelab/tofu/proxmox-host/<host>.tfstate`, encrypted (AES-GCM, key from a PBKDF2 passphrase) |
| Plugin and module data | `/var/lib/homelab/tofu/proxmox-host/<host>.data` (`TF_DATA_DIR`) |
| State passphrase | `iac/secrets/tofu/<host>-state.sops.yaml`, written by `init-passphrase` |
| API token | `iac/secrets/tofu/<host>-api.sops.yaml`, written by the `pve_api_identity` role |
| State copy before `apply`, `destroy`, `import` | `%LOCALAPPDATA%\homelab\tofu-state\` |

Plan and state encryption are both `enforced`: OpenTofu refuses to write plaintext. Losing the passphrase loses the state (ADR 0013).

## API path

The provider endpoint is `https://127.0.0.1:18006/`, the local end of an SSH forward to the host's `127.0.0.1:8006` that `tofu.sh` opens with the pinned host key (ADR 0029). The API token reaches the provider through `PROXMOX_VE_API_TOKEN` only. Plan and apply dial the API even for data sources, so they need the forward; `init`, `validate` and `fmt` do not.

## Checks without a host

```sh
tofu fmt -check -recursive iac/tofu
(cd iac/tofu/stacks && tflint --recursive --config "$PWD/../../../.tflint.hcl")
export TF_VAR_state_passphrase=local-test-only-passphrase-not-a-secret-0123   # needed by test only
tofu -chdir=iac/tofu/stacks/proxmox-host init -backend=false && tofu -chdir=iac/tofu/stacks/proxmox-host validate && tofu -chdir=iac/tofu/stacks/proxmox-host test
```
