variable "vm_id" {
  type        = number
  description = "Container VMID in Proxmox"
}

variable "node_name" {
  type        = string
  description = "Proxmox target node"
  default     = "pve"
}

variable "hostname" {
  type        = string
  description = "LXC container hostname"
}

variable "template_file" {
  type        = string
  description = "CT template storage path (e.g., local:vztmpl/debian-12-...)"
}

variable "cores" {
  type        = number
  description = "Number of vCPU cores"
  default     = 2
}

variable "memory_mb" {
  type        = number
  description = "RAM allocated in MiB"
  default     = 4096
}

variable "disk_size_gb" {
  type        = number
  description = "Root disk volume size in GB"
  default     = 30
}

variable "storage_pool" {
  type        = string
  description = "Storage pool for rootfs"
  default     = "local-lvm"
}

variable "bridge" {
  type        = string
  description = "Network bridge interface"
  default     = "vmbr1"
}

variable "ip_address" {
  type        = string
  description = "IPv4 CIDR address (e.g. 10.99.20.101/24)"
}

variable "gateway" {
  type        = string
  description = "Default IPv4 gateway"
  default     = "10.99.20.1"
}

variable "nesting" {
  type        = bool
  description = "Enable container nesting (required for Docker-in-LXC)"
  default     = true
}

variable "keyctl" {
  type        = bool
  description = "Enable keyctl feature (required for Docker overlay2)"
  default     = true
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to inject into container"
  default     = ""
}

variable "tags" {
  type        = list(string)
  description = "Tags to assign to the container"
  default     = ["ci-runner"]
}
