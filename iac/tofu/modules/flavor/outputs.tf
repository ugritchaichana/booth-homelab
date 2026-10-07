output "flavors" {
  description = "Every catalog entry keyed by provider/instance."
  value       = local.flavors
}

output "cores" {
  description = "vCPU count of the flavor."
  value       = local.size.cores

  precondition {
    condition     = local.size != null
    error_message = local.unknown_flavor_message
  }
}

output "memory_mb" {
  description = "Memory of the flavor in MiB."
  value       = local.size.memory_mb

  precondition {
    condition     = local.size != null
    error_message = local.unknown_flavor_message
  }
}

output "disk_gb" {
  description = "Root disk of the flavor in GiB."
  value       = local.size.disk_gb

  precondition {
    condition     = local.size != null
    error_message = local.unknown_flavor_message
  }
}

output "vm" {
  description = "Sizes for a VM; balloon is the catalog balloon_mb, or 0 (ballooning off) when the entry has none."
  value = {
    cores   = local.size.cores
    memory  = local.size.memory_mb
    balloon = lookup(local.size, "balloon_mb", 0)
    disk_gb = local.size.disk_gb
  }

  precondition {
    condition     = local.size != null
    error_message = local.unknown_flavor_message
  }
}

output "container" {
  description = "Sizes for an LXC container; it has no balloon option, and swap is 0."
  value = {
    cores   = local.size.cores
    memory  = local.size.memory_mb
    swap    = 0
    disk_gb = local.size.disk_gb
  }

  precondition {
    condition     = local.size != null
    error_message = local.unknown_flavor_message
  }
}
