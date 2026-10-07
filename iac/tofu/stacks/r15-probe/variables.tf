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

variable "import_datastore_id" {
  description = "Datastore with the import and vztmpl content types: receives the cloud image and the container template."
  type        = string
  default     = "local"
}

variable "lxc_template_name" {
  description = "Container template downloaded from the official Proxmox template mirror."
  type        = string
  default     = "debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "lxc_template_sha512" {
  description = "SHA512 of the template, from the mirror's aplinfo index and confirmed by hashing the file."
  type        = string
  default     = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"

  validation {
    condition     = can(regex("^[0-9a-f]{128}$", var.lxc_template_sha512))
    error_message = "lxc_template_sha512 must be 128 lowercase hexadecimal characters."
  }
}

variable "dns_server" {
  description = "Resolver written into both guests."
  type        = string
  default     = "1.1.1.1"
}

variable "image_directory" {
  description = "Dated directory of the Debian cloud image, never `latest`, which is rebuilt in place."
  type        = string
  default     = "20261001-2618"

  validation {
    condition     = can(regex("^[0-9]{8}-[0-9]+$", var.image_directory))
    error_message = "image_directory must be a dated directory such as 20261001-2618."
  }
}

variable "image_sha512" {
  description = "SHA512 of the image in image_directory, from the SHA512SUMS file next to it."
  type        = string
  default     = "f46f0671a6e5bdec5291ab8972bae2f10e5408c2f64a74078f11efc2f06a436a9d0313ed50e0472542eeabf780e9f7c792ac0a314c6c20507fcd9fd81b468c3d"

  validation {
    condition     = can(regex("^[0-9a-f]{128}$", var.image_sha512))
    error_message = "image_sha512 must be 128 lowercase hexadecimal characters."
  }
}
