resource "proxmox_virtual_environment_container" "sim_cache" {
  node_name     = local.node_name
  vm_id         = var.vm_id
  pool_id       = var.pool_id
  description   = "Simulation cache (object store and tailnet connector); configured by the sim_cache_service role"
  unprivileged  = true
  start_on_boot = true
  started       = false
  tags          = local.tags

  cpu {
    cores = 1
  }

  memory {
    dedicated = 1536
    swap      = 0
  }

  operating_system {
    template_file_id = local.template_file
    type             = "debian"
  }

  disk {
    datastore_id = var.vm_datastore_id
    size         = var.root_disk_gb
  }

  mount_point {
    volume = var.vm_datastore_id
    size   = "${var.data_disk_gb}G"
    path   = local.data_mount
  }

  network_interface {
    name     = "eth0"
    bridge   = local.vnet
    firewall = local.nic_firewall
  }

  initialization {
    hostname = local.hostname

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${local.address}/${local.prefix_length}"
        gateway = local.gateway
      }
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = local.sim_ready
      error_message = "The host entry in the inventory needs cache_network, cache_endpoint and sim_cache_endpoint (address) before this stack can plan."
    }

    precondition {
      condition     = !local.sim_ready || (cidrcontains(local.cache_network.cidr, local.address) && local.address != local.gateway && local.address != local.cache_endpoint.address)
      error_message = "The sim cache address must be a host address inside the cache subnet, other than the gateway and the build cache."
    }

    precondition {
      condition     = can(regex(local.name_pattern, local.hostname))
      error_message = "The sim cache hostname must be a valid hostname of at most 63 characters."
    }
  }
}

resource "proxmox_virtual_environment_firewall_options" "sim_cache" {
  node_name    = local.node_name
  container_id = proxmox_virtual_environment_container.sim_cache.vm_id

  enabled       = local.fw_options.enable == 1
  input_policy  = local.fw_options.policy_in
  output_policy = local.fw_options.policy_out
  ipfilter      = local.fw_options.ipfilter == 1
  macfilter     = local.fw_options.macfilter == 1
  dhcp          = local.fw_options.dhcp == 1
  radv          = local.fw_options.radv == 1
  ndp           = local.fw_options.ndp == 1
  log_level_out = local.fw_options.log_level_out
}

resource "proxmox_virtual_environment_firewall_rules" "sim_cache" {
  node_name    = local.node_name
  container_id = proxmox_virtual_environment_container.sim_cache.vm_id

  depends_on = [proxmox_virtual_environment_firewall_options.sim_cache]

  rule {
    security_group = local.egress_group
    comment        = "Runner-class egress"
  }

  rule {
    security_group = var.ingress_group
    comment        = "Runner subnet to the cache port, gateway to ssh"
  }
}
