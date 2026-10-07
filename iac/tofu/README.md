# OpenTofu

| Path | Purpose |
|---|---|
| `stacks/proxmox-host/` | The only root module; run it through the wrapper `scripts/iac/tofu.sh` (see its README). |
| `flavors.json` | Instance flavor catalog kept for the guest network and runner work of Phase 3; nothing reads it yet. |

CI finds root modules by layout, so a new stack is a new directory under `stacks/`.
