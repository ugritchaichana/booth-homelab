output "vm_id" {
  description = "Assigned container VMID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "Container hostname"
  value       = var.hostname
}

output "ip_address" {
  description = "Configured container IP address"
  value       = var.ip_address
}
