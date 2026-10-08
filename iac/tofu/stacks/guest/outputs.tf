output "guests" {
  value = {
    for key, guest in local.placed : key => {
      name           = guest.name
      kind           = guest.kind
      vm_id          = guest.vm_id
      address        = guest.address
      flavor         = guest.flavor
      cores          = module.flavor[guest.flavor].cores
      memory_mb      = module.flavor[guest.flavor].memory_mb
      disk_gb        = module.flavor[guest.flavor].disk_gb
      tags           = guest.tags
      vendor_snippet = guest.vendor_snippet
    }
  }

  precondition {
    condition     = length(local.placed) == length(local.sized_guests)
    error_message = "Every guest name <role>-<template class>-v<N> must be a lowercase hostname of at most 63 characters starting with a letter, so the role must be shorter and use only a-z, 0-9 and hyphen."
  }

  precondition {
    condition     = alltrue([for guest in values(local.guests) : guest.identity_ok])
    error_message = "Every guest key must be <role>-<template class>, with the class of its template_class and a non-empty role."
  }

  precondition {
    condition     = length(distinct([for guest in values(local.placed) : guest.name])) == length(local.placed)
    error_message = "Two guests compose the same name."
  }

  precondition {
    condition     = alltrue([for guest in values(local.guests) : guest.vendor_snippet == null || (guest.kind == "qemu" && can(regex("^[a-z0-9][a-z0-9-]*\\.ya?ml$", guest.vendor_snippet)))])
    error_message = "vendor_snippet is a file name such as lab-accounts-vendor.yaml in the host's snippets storage, and only a VM guest takes one."
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
