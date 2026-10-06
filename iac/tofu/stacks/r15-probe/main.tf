resource "proxmox_download_file" "image" {
  node_name          = local.node_name
  datastore_id       = var.import_datastore_id
  content_type       = "import"
  url                = local.image_url
  file_name          = local.image_file
  checksum           = var.image_sha512
  checksum_algorithm = "sha512"
}

resource "proxmox_download_file" "lxc_template" {
  node_name          = local.node_name
  datastore_id       = var.import_datastore_id
  content_type       = "vztmpl"
  url                = "http://download.proxmox.com/images/system/${local.template_file}"
  file_name          = local.template_file
  checksum           = var.lxc_template_sha512
  checksum_algorithm = "sha512"
}

resource "proxmox_virtual_environment_container" "probe" {
  node_name     = local.node_name
  vm_id         = local.guests.lxc.vm_id
  pool_id       = var.pool_id
  description   = "Throwaway R15 isolation probe"
  tags          = ["r15-probe"]
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

  disk {
    datastore_id = var.vm_datastore_id
    size         = 2
  }

  operating_system {
    template_file_id = proxmox_download_file.lxc_template.id
    type             = "debian"
  }

  network_interface {
    name     = "eth0"
    bridge   = local.guest_network.vnet
    firewall = local.nic_firewall
  }

  initialization {
    hostname = "r15-probe-lxc"

    dns {
      servers = [var.dns_server]
    }

    ip_config {
      ipv4 {
        address = "${local.guests.lxc.address}/${local.prefix_length}"
        gateway = local.guest_network.gateway
      }
    }

    user_account {
      keys = [var.probe_ssh_public_key]
    }
  }

  lifecycle {
    ignore_changes = [started]

    precondition {
      condition     = cidrcontains(local.guest_network.cidr, local.guests.lxc.address) && local.guests.lxc.address != local.guest_network.gateway
      error_message = "The probe container address must be a host address inside the guest subnet."
    }
  }
}

resource "proxmox_virtual_environment_vm" "probe" {
  name            = "r15-probe-vm"
  node_name       = local.node_name
  vm_id           = local.guests.vm.vm_id
  pool_id         = var.pool_id
  description     = "Throwaway R15 isolation probe"
  tags            = ["r15-probe"]
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

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = proxmox_download_file.image.id
    interface    = "scsi0"
    size         = 4
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
    datastore_id = var.vm_datastore_id

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

resource "proxmox_virtual_environment_firewall_options" "lxc" {
  node_name     = local.node_name
  container_id  = proxmox_virtual_environment_container.probe.vm_id
  enabled       = local.options.enable == 1
  input_policy  = local.options.policy_in
  output_policy = local.options.policy_out
  ipfilter      = local.options.ipfilter == 1
  log_level_out = local.options.log_level_out
  macfilter     = local.options.macfilter == 1
  dhcp          = local.options.dhcp == 1
  radv          = local.options.radv == 1
  ndp           = local.options.ndp == 1
}

resource "proxmox_virtual_environment_firewall_options" "vm" {
  node_name     = local.node_name
  vm_id         = proxmox_virtual_environment_vm.probe.vm_id
  enabled       = local.options.enable == 1
  input_policy  = local.options.policy_in
  output_policy = local.options.policy_out
  ipfilter      = local.options.ipfilter == 1
  log_level_out = local.options.log_level_out
  macfilter     = local.options.macfilter == 1
  dhcp          = local.options.dhcp == 1
  radv          = local.options.radv == 1
  ndp           = local.options.ndp == 1

  depends_on = [proxmox_virtual_environment_firewall_ipset.vm_ipfilter]
}

resource "proxmox_virtual_environment_firewall_rules" "lxc" {
  node_name    = local.node_name
  container_id = proxmox_virtual_environment_container.probe.vm_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.probe.r15_control_port)
    source  = local.guest_network.gateway
    comment = "Control channel from the host"
    enabled = true
  }

  rule {
    security_group = local.policy.runner_class_security_group
    comment        = "Egress policy"
    enabled        = true
  }
}

resource "proxmox_virtual_environment_firewall_rules" "vm" {
  node_name = local.node_name
  vm_id     = proxmox_virtual_environment_vm.probe.vm_id

  rule {
    type    = "in"
    action  = "ACCEPT"
    proto   = "tcp"
    dport   = tostring(local.probe.r15_control_port)
    source  = local.guest_network.gateway
    comment = "Control channel from the host"
    enabled = true
  }

  rule {
    security_group = local.policy.runner_class_security_group
    comment        = "Egress policy"
    enabled        = true
  }
}
