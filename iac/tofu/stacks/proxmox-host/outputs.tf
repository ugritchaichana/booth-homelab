output "host" {
  value = var.host
}

output "node_name" {
  value = local.node_name
}

output "pve_version" {
  value = data.proxmox_version.this.version
}

output "guest_network" {
  value = {
    zone    = module.guest_network.zone
    vnet    = module.guest_network.vnet
    cidr    = module.guest_network.cidr
    gateway = module.guest_network.gateway
  }
}

output "cache_network" {
  value = local.cache_network == null ? null : {
    vnet    = local.cache_network.vnet
    cidr    = module.guest_network.additional_vnets[local.cache_network.vnet].cidr
    gateway = module.guest_network.additional_vnets[local.cache_network.vnet].gateway
  }
}
