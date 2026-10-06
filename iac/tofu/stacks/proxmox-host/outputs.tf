output "host" {
  value = var.host
}

output "node_name" {
  value = local.node_name
}

output "pve_version" {
  value = data.proxmox_version.this.version
}
