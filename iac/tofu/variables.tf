# ==============================================================================
# OpenTofu Input Variables & Multi-Cloud Flavor Selectors
# ==============================================================================

variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox VE API endpoint URL (e.g., https://pve.example.local:8006/)"
  default     = ""
}

variable "proxmox_insecure" {
  type        = bool
  description = "Allow self-signed or untrusted SSL certificates on Proxmox VE API"
  default     = true
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox VE administrative username"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "Proxmox VE administrative password (set via vault or TF_VAR_proxmox_password)"
  sensitive   = true
  default     = ""
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox VE API token in format USER@REALM!TOKENID=UUID"
  sensitive   = true
  default     = ""
}

variable "proxmox_node" {
  type        = string
  description = "Target Proxmox node name"
  default     = "pve"
}

# ------------------------------------------------------------------------------
# Multi-Cloud Instance Flavor Selectors
# ------------------------------------------------------------------------------

variable "cloud_provider" {
  type        = string
  description = "Active cloud provider catalog abstraction: aws, gcp, azure, hetzner, digitalocean"
  default     = "aws"

  validation {
    condition     = contains(["aws", "gcp", "azure", "hetzner", "digitalocean"], var.cloud_provider)
    error_message = "cloud_provider must be one of: aws, gcp, azure, hetzner, digitalocean."
  }
}

variable "runner_dotnet_flavor" {
  type        = string
  description = "Instance flavor for CT 102 (.NET Runner). E.g. 't3.medium' for AWS, 'e2-medium' for GCP, 'cx22' for Hetzner."
  default     = "t3.medium"
}

variable "runner_angular_flavor" {
  type        = string
  description = "Instance flavor for CT 103 (Angular Runner). E.g. 't3.small' for AWS, 'e2-small' for GCP, 'cx22' for Hetzner."
  default     = "t3.small"
}

variable "minio_cache_flavor" {
  type        = string
  description = "Instance flavor for CT 104 (MinIO S3 Cache). E.g. 't3.small' for AWS, 'e2-small' for GCP, 'cx22' for Hetzner."
  default     = "t3.small"
}

# ------------------------------------------------------------------------------
# Network & Storage Settings
# ------------------------------------------------------------------------------

variable "bridge" {
  type        = string
  description = "Isolated internal bridge interface on Proxmox node"
  default     = "vmbr1"
}

variable "gateway" {
  type        = string
  description = "Default IPv4 gateway on isolated bridge"
  default     = "10.99.20.1"
}

variable "storage_pool" {
  type        = string
  description = "Target Proxmox storage pool for root disks"
  default     = "local-lvm"
}

variable "template_storage_pool" {
  type        = string
  description = "Target Proxmox storage pool containing CT templates / ISOs"
  default     = "local"
}

variable "debian_template" {
  type        = string
  description = "Debian 12 CT template path on storage_pool"
  default     = "local:vztmpl/debian-12-standard_12.7-1_amd64.tar.zst"
}

variable "alpine_template" {
  type        = string
  description = "Alpine 3.23 CT template path on storage_pool"
  default     = "local:vztmpl/alpine-3.23-default_20241201_amd64.tar.xz"
}

variable "ssh_public_key" {
  type        = string
  description = "Public SSH key injected into containers for non-interactive administration"
  default     = ""
}
