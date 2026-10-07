locals {
  inventory_path = coalesce(var.inventory_file, "${path.module}/../../../inventory/hosts.yml")
  inventory      = yamldecode(file(local.inventory_path))
  pve_hosts      = local.inventory.all.children.pve_hosts.hosts
  node_name      = local.pve_hosts[var.host].pve_node_name

  cache_network  = try(local.pve_hosts[var.host].cache_network, null)
  cache_endpoint = try(local.pve_hosts[var.host].cache_endpoint, null)
  cache_ready    = local.cache_network != null && local.cache_endpoint != null
  vnet           = try(local.cache_network.vnet, "")
  gateway        = try(local.cache_network.gateway, "")
  address        = try(local.cache_endpoint.address, "")
  prefix_length  = try(split("/", local.cache_network.cidr)[1], "24")

  policy        = yamldecode(file("${path.module}/../../../policy/runner-class.yml"))
  service       = yamldecode(file("${path.module}/../../../ansible/roles/cache_service/defaults/main.yml"))
  templates     = yamldecode(file("${path.module}/../../../ansible/roles/pve_templates/defaults/main.yml"))
  fw_options    = local.policy.runner_class_firewall_options
  egress_group  = local.policy.runner_class_security_group
  nic_firewall  = local.policy.runner_class_nic_firewall == 1
  template_file = local.templates.pve_templates_classes["lxc-runner"].base
  data_mount    = local.service.cache_service_data_mount
  max_size_gib  = local.service.cache_service_max_size_gib

  reserved_vm_ids = concat(
    local.templates.pve_templates_reserved_vmids,
    flatten([for c in values(local.templates.pve_templates_classes) : range(c.vmid_base, c.vmid_base + 100)]),
  )
}
