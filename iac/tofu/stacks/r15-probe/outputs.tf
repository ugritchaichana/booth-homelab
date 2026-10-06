output "guests" {
  value = {
    for name, guest in local.guests : name => {
      kind    = guest.kind
      vm_id   = guest.vm_id
      address = guest.address
    }
  }
}

output "image_url" {
  value = local.image_url
}
