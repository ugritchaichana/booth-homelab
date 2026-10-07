output "cache" {
  value = {
    vm_id   = proxmox_virtual_environment_container.cache.vm_id
    address = local.address
    port    = try(local.cache_endpoint.port, null)
  }
}
