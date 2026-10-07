# Token comes from PROXMOX_VE_API_TOKEN; insecure is safe only on the SSH-pinned loopback forward.
provider "proxmox" {
  endpoint = var.api_endpoint
  insecure = true
}
