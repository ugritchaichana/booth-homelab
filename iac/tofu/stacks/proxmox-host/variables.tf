variable "host" {
  description = "Inventory host name this run manages."
  type        = string

  validation {
    condition     = contains(keys(local.pve_hosts), var.host)
    error_message = "host must be a pve_hosts entry in iac/inventory/hosts.yml."
  }
}

variable "state_passphrase" {
  description = "Passphrase of the state and plan encryption key."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "state_passphrase must be at least 32 characters."
  }
}

variable "api_endpoint" {
  description = "Proxmox API endpoint; the SSH forward opened by scripts/iac/tofu.sh."
  type        = string
  default     = "https://127.0.0.1:18006/"

  validation {
    condition     = can(regex("^https://127[.]0[.]0[.]1:[0-9]{1,5}/$", var.api_endpoint))
    error_message = "api_endpoint must be a loopback https URL ending in a slash."
  }
}
