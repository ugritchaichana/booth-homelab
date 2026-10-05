# ==============================================================================
# Multi-Cloud Instance Flavor Catalog Engine
# ==============================================================================
# Ingests flavors.json and resolves public cloud instance types (AWS, GCP, Azure,
# Hetzner, DigitalOcean) into concrete Proxmox VE hardware parameters (vCPU, RAM, Disk).

locals {
  flavor_catalog = jsondecode(file("${path.module}/flavors.json"))

  # Supported providers list
  supported_providers = keys(local.flavor_catalog.providers)

  # Helper to resolve an instance type for a given cloud provider
  # Returns: { cores, memory_mb, disk_gb, balloon_mb, description }
  resolve_flavor = {
    for p, p_data in local.flavor_catalog.providers :
    p => {
      for inst_name, inst_specs in p_data.instances :
      inst_name => inst_specs
    }
  }
}
