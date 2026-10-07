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

variable "guests_file" {
  description = "Guest list to read; null selects guests.yml next to this stack. Tests point it at a fixture."
  type        = string
  default     = null
}

variable "guest_budget" {
  description = "Largest size one guest may have; the defaults are the whole of the Proxmox VM in ADR 0003 (12 vCPU, 20 GiB RAM, 128 GiB disk)."
  type = object({
    cores     = number
    memory_mb = number
    disk_gb   = number
  })
  default = {
    cores     = 12
    memory_mb = 20480
    disk_gb   = 128
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
  description = "Resolver written into every guest."
  type        = string
  default     = "1.1.1.1"
}

variable "template_pool_id" {
  description = "Pool the golden templates must be members of (ADR 0036)."
  type        = string
  default     = "templates"
}
