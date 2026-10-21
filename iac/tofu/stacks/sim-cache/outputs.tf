output "sim_cache" {
  value = {
    vm_id   = proxmox_virtual_environment_container.sim_cache.vm_id
    address = local.address
  }
}
