locals {
  inventory = yamldecode(file("${path.module}/../../../inventory/hosts.yml"))
  pve_hosts = local.inventory.all.children.pve_hosts.hosts
  node_name = local.pve_hosts[var.host].pve_node_name
}
