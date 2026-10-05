variable "vm_id" {
  type        = number
  description = "Container VMID for MinIO S3"
  default     = 104
}

variable "node_name" {
  type        = string
  description = "Proxmox target node"
  default     = "pve"
}

variable "hostname" {
  type        = string
  description = "MinIO container hostname"
  default     = "minio-s3"
}

variable "template_file" {
  type        = string
  description = "Alpine CT template path"
}

variable "cores" {
  type        = number
  description = "Number of vCPU cores"
  default     = 2
}

variable "memory_mb" {
  type        = number
  description = "RAM allocated in MiB"
  default     = 2048
}

variable "disk_size_gb" {
  type        = number
  description = "Root disk volume size in GB"
  default     = 20
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
  description = "IPv4 CIDR address (e.g. 10.99.20.20/24)"
  default     = "10.99.20.20/24"
}

variable "gateway" {
  type        = string
  description = "Default IPv4 gateway"
  default     = "10.99.20.1"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key"
  default     = ""
}
