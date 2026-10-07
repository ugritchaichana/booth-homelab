output "guests" {
  value = {
    for name, guest in local.guests : name => {
      kind    = guest.kind
      name    = local.names[name]
      vm_id   = guest.vm_id
      address = guest.address
    }
  }
}

output "template_sources" {
  value = { for class, source in module.template_source : class => source.vmid }
}
