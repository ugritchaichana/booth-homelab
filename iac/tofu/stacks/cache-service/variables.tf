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

variable "ssh_public_keys" {
  description = "Public keys installed for root at create; Ansible reaches the container with the matching private key through pve01."
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0 && alltrue([for k in var.ssh_public_keys : can(regex("^ssh-ed25519 [A-Za-z0-9+/=]+( .*)?$", k))])
    error_message = "ssh_public_keys must hold at least one ssh-ed25519 public key line and no private key."
  }
}

variable "vm_id" {
  description = "Container id; must stay outside the template blocks and the probe ids."
  type        = number
  default     = 9050

  validation {
    condition     = !contains(local.reserved_vm_ids, var.vm_id)
    error_message = "vm_id collides with a template block or a reserved probe id."
  }
}

variable "pool_id" {
  description = "Resource pool the token may allocate guests in."
  type        = string
  default     = "homelab"
}

variable "vm_datastore_id" {
  description = "Datastore holding the root and data volumes."
  type        = string
  default     = "local-lvm"
}

variable "root_disk_gb" {
  description = "Root filesystem size."
  type        = number
  default     = 4
}

variable "data_disk_gb" {
  description = "Size of the cache data volume mounted at the service data mount."
  type        = number
  default     = 10
}

variable "dns_server" {
  description = "Resolver written into the container."
  type        = string
  default     = "1.1.1.1"
}

variable "ingress_group" {
  description = "Security group that admits the runner subnet to the cache port and the gateway to ssh."
  type        = string
  default     = "cache-ingress"
}
