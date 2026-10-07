output "zone" {
  value = proxmox_sdn_zone_simple.this.id
}

output "vnet" {
  value = proxmox_sdn_vnet.this.id
}

output "cidr" {
  value = proxmox_sdn_subnet.this.cidr
}

output "gateway" {
  value = proxmox_sdn_subnet.this.gateway
}
