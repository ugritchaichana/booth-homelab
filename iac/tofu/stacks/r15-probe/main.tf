module "template_source" {
  source   = "../../modules/proxmox/template-source"
  for_each = toset([for guest in values(local.guests) : guest.template_class])

  node    = local.node_name
  class   = each.key
  pin     = lookup(var.template_pins, each.key, null)
  pool_id = var.template_pool_id
}

resource "proxmox_virtual_environment_container" "probe" {
  node_name     = local.node_name
  vm_id         = local.guests.lxc.vm_id
  pool_id       = var.pool_id
  description   = "Throwaway R15 isolation probe"
  unprivileged  = true
  start_on_boot = true
  started       = false

  cpu {
    cores = 1
  }

  memory {
    dedicated = 256
    swap      = 0
  }

  tags = local.tags.lxc

  clone {
    vm_id = module.template_source[local.guests.lxc.template_class].vmid
    full  = false
  }

  disk {
    datastore_id = var.vm_datastore_id
    size         = module.template_source[local.guests.lxc.template_class].disk_gb
  }

  network_interface {
    name     = "eth0"
    bridge   = local.guest_network.vnet
    firewall = local.nic_firewall
  }

  initialization {
    hostname = local.names.lxc

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${local.guests.lxc.address}/${local.prefix_length}"
        gateway = local.guest_network.gateway
      }
    }
  }

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = cidrcontains(local.guest_network.cidr, local.guests.lxc.address) && local.guests.lxc.address != local.guest_network.gateway
      error_message = "The probe container address must be a host address inside the guest subnet."
    }

    precondition {
      condition     = local.names.lxc != null && can(regex(local.name_pattern, local.names.lxc))
      error_message = "The probe container name must be r15-probe-<template class>-v<N> and a hostname of at most 63 characters."
    }
  }
}

resource "proxmox_virtual_environment_vm" "probe" {
  name            = local.names.vm
  node_name       = local.node_name
  vm_id           = local.guests.vm.vm_id
  pool_id         = var.pool_id
  description     = "Throwaway R15 isolation probe"
  on_boot         = true
  started         = false
  stop_on_destroy = true

  agent {
    enabled = false
  }

  cpu {
    cores = 1
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 512
  }

  tags = local.tags.vm

  clone {
    vm_id = module.template_source[local.guests.vm.template_class].vmid
    full  = false
  }

  disk {
    datastore_id = var.vm_datastore_id
    interface    = "scsi0"
    size         = module.template_source[local.guests.vm.template_class].disk_gb
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
    vendor_data_file_id = "local:snippets/${local.probe.r15_vendor_snippet}"

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${local.guests.vm.address}/${local.prefix_length}"
        gateway = local.guest_network.gateway
      }
    }

    user_account {
      username = local.guests.vm.login_user
      keys     = [var.probe_ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = cidrcontains(local.guest_network.cidr, local.guests.vm.address) && local.guests.vm.address != local.guest_network.gateway
      error_message = "The probe VM address must be a host address inside the guest subnet."
    }

    precondition {
      condition     = local.names.vm != null && can(regex(local.name_pattern, local.names.vm))
      error_message = "The probe VM name must be r15-probe-<template class>-v<N> and a hostname of at most 63 characters."
    }
  }
}

resource "proxmox_virtual_environment_firewall_ipset" "vm_ipfilter" {
  node_name = local.node_name
  vm_id     = proxmox_virtual_environment_vm.probe.vm_id
  name      = "ipfilter-net0"
  comment   = "Source address the VM may use"

  cidr {
    name = local.guests.vm.address
  }
}
