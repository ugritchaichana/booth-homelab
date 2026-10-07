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

variable "inventory_file" {
  description = "Inventory file to read; null selects iac/inventory/hosts.yml. Tests point it at a fixture."
  type        = string
  default     = null
}

variable "probe_ssh_public_key" {
  description = "Public half of the throwaway key generated on the Proxmox host; the private half never leaves it."
  type        = string

  validation {
    condition     = can(regex("^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$", var.probe_ssh_public_key))
    error_message = "probe_ssh_public_key must be one ssh-ed25519 public key line."
  }
}

variable "pool_id" {
  description = "Resource pool the token may allocate guests in."
  type        = string
  default     = "homelab"
}

variable "vm_datastore_id" {
  description = "Datastore holding the guest disks."
  type        = string
  default     = "local-lvm"
}

variable "dns_server" {
  description = "Resolver written into both guests."
  type        = string
  default     = "1.1.1.1"
}

variable "template_pool_id" {
  description = "Pool the golden templates must be members of (ADR 0036)."
  type        = string
  default     = "templates"
}

variable "template_pins" {
  description = "Template class to version N. A class listed here clones v<N> instead of the guest tagged current (ADR 0044)."
  type        = map(number)
  default     = {}

  validation {
    condition     = alltrue([for n in values(var.template_pins) : n >= 1 && floor(n) == n])
    error_message = "Each pin must be a whole number of at least 1."
  }
}
