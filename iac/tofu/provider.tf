# ==============================================================================
# Proxmox VE OpenTofu / Terraform Provider Configuration
# ==============================================================================
# Provider: bpg/proxmox (Official modern Proxmox provider for OpenTofu / Terraform)
# Target: Proxmox VE 8.4 Hypervisor via Tailscale Mesh or Internal Gateway

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = var.proxmox_insecure

  # Authenticate via API Token (Recommended for CI/CD) or Credentials
  api_token = var.proxmox_api_token != "" ? var.proxmox_api_token : null
  username  = var.proxmox_api_token == "" ? var.proxmox_username : null
  password  = var.proxmox_api_token == "" ? var.proxmox_password : null

  ssh {
    agent    = false
    username = "root"
    password = var.proxmox_password
  }
}
