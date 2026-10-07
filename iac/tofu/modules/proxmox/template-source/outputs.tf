output "vmid" {
  description = "VMID of the one template selected by the current tag, or by the pin."
  value       = local.one_match ? local.match.vm_id : null

  precondition {
    condition     = local.spec != null
    error_message = "class ${var.class} is not a pve_templates_classes entry (lxc-runner or vm-docker)."
  }

  precondition {
    condition     = local.one_match
    error_message = "Expected exactly one ${var.class} guest in pool ${var.pool_id} on ${var.node} tagged ${local.marker}, ${var.class} and ${local.want_tag}, found ${length(local.matches)} (${local.selector})."
  }

  precondition {
    condition     = local.one_match ? local.match.template == true : true
    error_message = "The guest selected for ${var.class} by ${local.selector} is not a template."
  }

  precondition {
    condition     = local.one_match ? (local.match.vm_id >= local.block_first && local.match.vm_id <= local.block_last) : true
    error_message = "The ${var.class} template selected by ${local.selector} is outside the VMID block ${local.block_first}-${local.block_last}."
  }
}

output "disk_gb" {
  description = "Root disk size of the class in GiB; a clone keeps it, so a consumer declares the same number."
  value       = try(local.spec.disk_gb, null)
}

output "type" {
  description = "Guest kind of the class: lxc or qemu."
  value       = try(local.spec.type, null)
}
