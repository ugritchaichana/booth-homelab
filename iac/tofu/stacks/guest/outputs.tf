output "guests" {
  value = {
    for name, guest in local.sized_guests : name => {
      kind      = guest.kind
      vm_id     = guest.vm_id
      address   = guest.address
      flavor    = guest.flavor
      cores     = module.flavor[guest.flavor].cores
      memory_mb = module.flavor[guest.flavor].memory_mb
      disk_gb   = module.flavor[guest.flavor].disk_gb
      tags      = guest.tags
    }
  }

  precondition {
    condition     = alltrue([for name in keys(local.guests) : can(regex(local.name_pattern, name))])
    error_message = "Every guest name must be a lowercase hostname of at most 63 characters starting with a letter."
  }

  precondition {
    condition     = alltrue([for guest in values(local.guests) : contains(local.known_flavors, guest.flavor)])
    error_message = "flavor of every guest must be a provider/instance key of iac/tofu/flavors.json."
  }

  precondition {
    condition     = alltrue([for guest in values(local.guests) : guest.kind != null])
    error_message = "template_class of every guest must be a pve_templates_classes key (lxc-runner or vm-docker)."
  }

  precondition {
    condition     = alltrue([for guest in values(local.guests) : guest.slot != null && guest.slot >= local.slot_min && guest.slot <= local.slot_max && floor(guest.slot) == guest.slot])
    error_message = "slot of every guest must be a whole number from ${local.slot_min} to ${local.slot_max}."
  }

  precondition {
    condition     = length(distinct([for guest in values(local.guests) : guest.slot])) == length(local.guests)
    error_message = "Two guests share a slot, so they would share an address and a VMID."
  }
}

output "template_sources" {
  value = { for key, source in module.template_source : key => source.vmid }
}
