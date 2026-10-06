locals {
  inventory_path = coalesce(var.inventory_file, "${path.module}/../../../inventory/hosts.yml")
  inventory      = yamldecode(file(local.inventory_path))
  pve_hosts      = local.inventory.all.children.pve_hosts.hosts
  node_name      = local.pve_hosts[var.host].pve_node_name
  guest_network  = local.pve_hosts[var.host].guest_network
  prefix_length  = split("/", local.guest_network.cidr)[1]

  probe        = yamldecode(file("${path.module}/probe.yml"))
  policy       = yamldecode(file("${path.module}/../../../policy/runner-class.yml"))
  guests       = local.probe.r15_guests
  options      = local.policy.runner_class_firewall_options
  nic_firewall = local.policy.runner_class_nic_firewall == 1

  template_file = var.lxc_template_name
  image_file    = "debian-13-genericcloud-amd64-${var.image_directory}.qcow2"
  image_url     = "https://cloud.debian.org/images/cloud/trixie/${var.image_directory}/${local.image_file}"
}
