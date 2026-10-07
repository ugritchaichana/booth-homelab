locals {
  defaults = yamldecode(file(coalesce(var.classes_file, "${path.module}/../../../../ansible/roles/pve_templates/defaults/main.yml")))
  spec     = lookup(local.defaults.pve_templates_classes, var.class, null)
  marker   = local.defaults.pve_templates_marker_tag
  is_lxc   = try(local.spec.type == "lxc", false)

  block_first = try(local.spec.vmid_base, 0)
  block_last  = local.block_first + 99
  want_tag    = var.pin == null ? "current" : "v${var.pin}"
  selector    = var.pin == null ? "the current tag" : "pin v${var.pin}"

  guests = local.is_lxc ? data.proxmox_virtual_environment_containers.all[0].containers : data.proxmox_virtual_environment_vms.all[0].vms

  matches = [
    for g in local.guests : g
    if g.node_name == var.node
    && contains(g.tags, local.marker)
    && contains(g.tags, var.class)
    && contains(g.tags, local.want_tag)
  ]

  one_match = length(local.matches) == 1
  match     = local.one_match ? local.matches[0] : null

  pool_kind    = local.is_lxc ? "lxc" : "qemu"
  pool_members = [for m in data.proxmox_virtual_environment_pool.templates.members : m.vm_id if m.type == local.pool_kind && m.node_name == var.node]
}

data "proxmox_virtual_environment_containers" "all" {
  count     = local.is_lxc ? 1 : 0
  node_name = var.node
}

data "proxmox_virtual_environment_vms" "all" {
  count     = local.is_lxc ? 0 : 1
  node_name = var.node
}

data "proxmox_virtual_environment_pool" "templates" {
  pool_id = var.pool_id
}
