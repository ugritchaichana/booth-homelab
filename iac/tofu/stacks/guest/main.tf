module "template_source" {
  source   = "../../modules/proxmox/template-source"
  for_each = local.template_sources

  node    = local.node_name
  class   = each.value.class
  pin     = each.value.pin
  pool_id = var.template_pool_id
}

module "flavor" {
  source   = "../../modules/flavor"
  for_each = local.flavor_names

  flavor = each.key
}

moved {
  from = proxmox_virtual_environment_container.guest["demo"]
  to   = proxmox_virtual_environment_container.guest["demo-lxc-runner"]
}

resource "proxmox_virtual_environment_container" "guest" {
  for_each = local.lxc_guests

  node_name     = local.node_name
  vm_id         = each.value.vm_id
  pool_id       = var.pool_id
  description   = "Flavor guest ${each.value.flavor}"
  unprivileged  = true
  start_on_boot = true
  started       = false

  cpu {
    cores = module.flavor[each.value.flavor].container.cores
  }

  memory {
    dedicated = module.flavor[each.value.flavor].container.memory
    swap      = module.flavor[each.value.flavor].container.swap
  }

  tags = each.value.tags

  clone {
    vm_id = module.template_source[each.value.source_key].vmid
    full  = false
  }

  disk {
    datastore_id = var.vm_datastore_id
    size         = module.flavor[each.value.flavor].container.disk_gb
  }

  network_interface {
    name     = "eth0"
    bridge   = local.guest_network.vnet
    firewall = local.nic_firewall
  }

  initialization {
    hostname = each.value.name

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${each.value.address}/${local.prefix_length}"
        gateway = local.guest_network.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = each.value.address != null && cidrcontains(local.guest_network.cidr, each.value.address) && each.value.address != local.guest_network.gateway
      error_message = "Guest ${each.key} needs a host address inside the guest subnet."
    }

    precondition {
      condition     = module.flavor[each.value.flavor].cores <= var.guest_budget.cores && module.flavor[each.value.flavor].memory_mb <= var.guest_budget.memory_mb && module.flavor[each.value.flavor].disk_gb <= var.guest_budget.disk_gb
      error_message = "Flavor ${each.value.flavor} of guest ${each.key} is larger than the host budget guest_budget."
    }

    precondition {
      condition     = module.flavor[each.value.flavor].disk_gb >= module.template_source[each.value.source_key].disk_gb
      error_message = "Flavor ${each.value.flavor} has a disk smaller than the ${each.value.template_class} template; a clone disk only grows."
    }
  }
}

resource "proxmox_virtual_environment_vm" "guest" {
  for_each = local.vm_guests

  name            = each.value.name
  node_name       = local.node_name
  vm_id           = each.value.vm_id
  pool_id         = var.pool_id
  description     = "Flavor guest ${each.value.flavor}"
  on_boot         = true
  started         = false
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = module.flavor[each.value.flavor].vm.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = module.flavor[each.value.flavor].vm.memory
    floating  = module.flavor[each.value.flavor].vm.balloon
  }

  tags = each.value.tags

  clone {
    vm_id = module.template_source[each.value.source_key].vmid
    full  = false
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = module.flavor[each.value.flavor].vm.disk_gb
    discard      = "on"
  }

  network_device {
    bridge   = local.guest_network.vnet
    model    = "virtio"
    firewall = local.nic_firewall
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id        = var.vm_datastore_id
    vendor_data_file_id = each.value.vendor_snippet == null ? null : "local:snippets/${each.value.vendor_snippet}"

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${each.value.address}/${local.prefix_length}"
        gateway = local.guest_network.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [started, pool_id]

    precondition {
      condition     = each.value.address != null && cidrcontains(local.guest_network.cidr, each.value.address) && each.value.address != local.guest_network.gateway
      error_message = "Guest ${each.key} needs a host address inside the guest subnet."
    }

    precondition {
      condition     = module.flavor[each.value.flavor].cores <= var.guest_budget.cores && module.flavor[each.value.flavor].memory_mb <= var.guest_budget.memory_mb && module.flavor[each.value.flavor].disk_gb <= var.guest_budget.disk_gb
      error_message = "Flavor ${each.value.flavor} of guest ${each.key} is larger than the host budget guest_budget."
    }

    precondition {
      condition     = module.flavor[each.value.flavor].disk_gb >= module.template_source[each.value.source_key].disk_gb
      error_message = "Flavor ${each.value.flavor} has a disk smaller than the ${each.value.template_class} template; a clone disk only grows."
    }
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "vm_ipfilter" {
  for_each = local.vm_guests

  node_name = local.node_name
  vm_id     = proxmox_virtual_environment_vm.guest[each.key].vm_id
  name      = "ipfilter-net0"
  comment   = "Source address the VM may use"

  cidr {
    name = each.value.address
  }
}
