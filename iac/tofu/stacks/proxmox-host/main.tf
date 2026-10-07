data "proxmox_version" "this" {}

module "guest_network" {
  source = "../../modules/proxmox/sdn"

  zone    = local.guest_network.zone
  vnet    = local.guest_network.vnet
  nodes   = [local.node_name]
  cidr    = local.guest_network.cidr
  gateway = local.guest_network.gateway
}
