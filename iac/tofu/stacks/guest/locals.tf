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
    for key, guest in local.declared : key => {
      flavor         = guest.flavor
      template_class = guest.template_class
      identity_ok    = endswith(key, "-${guest.template_class}") && length(key) > length(guest.template_class) + 1
      kind           = try(local.classes[guest.template_class].type, null)
      version        = try(guest.template_version, null)
      source_key     = try(guest.template_version, null) == null ? guest.template_class : "${guest.template_class}-v${guest.template_version}"
      slot           = try(tonumber(guest.slot), null)
      address        = try(cidrhost(local.guest_network.cidr, local.address_base + tonumber(guest.slot)), null)
      vm_id          = try(local.vm_id_base + tonumber(guest.slot), null)
      vendor_snippet = try(guest.vendor_snippet, null)
    }
  }

  catalog_providers = jsondecode(file("${path.module}/../../flavors.json")).providers
  known_flavors     = toset(flatten([for provider, spec in local.catalog_providers : [for instance in keys(spec.instances) : "${provider}/${instance}"]]))
  flavor_names      = toset([for guest in values(local.declared) : guest.flavor if contains(local.known_flavors, guest.flavor)])
  name_pattern      = "^[a-z][a-z0-9-]{0,62}$"
  sized_guests      = { for key, guest in local.guests : key => guest if contains(local.known_flavors, guest.flavor) && guest.kind != null }

  cloned_versions = { for key, guest in local.sized_guests : key => module.template_source[guest.source_key].version }
  names           = { for key, guest in local.sized_guests : key => local.cloned_versions[key] == null ? null : "${key}-v${local.cloned_versions[key]}" }

  placed = {
    for key, guest in local.sized_guests : key => merge(guest, {
      name = local.names[key]
      tags = sort([
        "flavor-guest",
        "flavor-${replace(lower(guest.flavor), "/[^a-z0-9_.+-]/", "-")}",
        "src-${guest.template_class}-v${local.cloned_versions[key]}",
      ])
    }) if can(regex(local.name_pattern, local.names[key]))
  }

  lxc_guests = { for key, guest in local.placed : key => guest if guest.kind == "lxc" }
  vm_guests  = { for key, guest in local.placed : key => guest if guest.kind == "qemu" }

  template_sources = {
    for key, group in { for guest in values(local.guests) : guest.source_key => guest... } : key => {
      class = group[0].template_class
      pin   = group[0].version
    } if group[0].kind != null
  }
}
