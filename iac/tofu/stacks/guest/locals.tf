locals {
  inventory_path = coalesce(var.inventory_file, "${path.module}/../../../inventory/hosts.yml")
  inventory      = yamldecode(file(local.inventory_path))
  pve_hosts      = local.inventory.all.children.pve_hosts.hosts
  node_name      = local.pve_hosts[var.host].pve_node_name
  guest_network  = local.pve_hosts[var.host].guest_network
  prefix_length  = split("/", local.guest_network.cidr)[1]

  policy       = yamldecode(file("${path.module}/../../../policy/runner-class.yml"))
  classes      = yamldecode(file("${path.module}/../../../ansible/roles/pve_templates/defaults/main.yml")).pve_templates_classes
  nic_firewall = local.policy.runner_class_nic_firewall == 1

  slot_min     = 1
  slot_max     = 99
  address_base = 100
  vm_id_base   = 9500

  declared = lookup(yamldecode(file(coalesce(var.guests_file, "${path.module}/guests.yml"))).guests, var.host, {})

  guests = {
    for name, guest in local.declared : name => {
      flavor         = guest.flavor
      template_class = guest.template_class
      kind           = try(local.classes[guest.template_class].type, null)
      version        = try(guest.template_version, null)
      source_key     = try(guest.template_version, null) == null ? guest.template_class : "${guest.template_class}-v${guest.template_version}"
      slot           = try(tonumber(guest.slot), null)
      address        = try(cidrhost(local.guest_network.cidr, local.address_base + tonumber(guest.slot)), null)
      vm_id          = try(local.vm_id_base + tonumber(guest.slot), null)
      tags           = ["flavor-guest", "flavor-${replace(lower(guest.flavor), "/[^a-z0-9_.+-]/", "-")}"]
    }
  }

  catalog_providers = jsondecode(file("${path.module}/../../flavors.json")).providers
  known_flavors     = toset(flatten([for provider, spec in local.catalog_providers : [for instance in keys(spec.instances) : "${provider}/${instance}"]]))
  flavor_names      = toset([for guest in values(local.declared) : guest.flavor if contains(local.known_flavors, guest.flavor)])
  name_pattern      = "^[a-z][a-z0-9-]{0,62}$"
  sized_guests      = { for name, guest in local.guests : name => guest if contains(local.known_flavors, guest.flavor) && can(regex(local.name_pattern, name)) }

  lxc_guests = { for name, guest in local.sized_guests : name => guest if guest.kind == "lxc" }
  vm_guests  = { for name, guest in local.sized_guests : name => guest if guest.kind == "qemu" }

  template_sources = {
    for key, group in { for guest in values(local.guests) : guest.source_key => guest... } : key => {
      class = group[0].template_class
      pin   = group[0].version
    } if group[0].kind != null
  }
}
