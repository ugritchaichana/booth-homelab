mock_provider "proxmox" {}

override_data {
  target = module.template_source["lxc-runner"].data.proxmox_virtual_environment_pool.templates
  values = {
    members = [
      { id = "lxc/9202", node_name = "pve01", type = "lxc", vm_id = 9202, datastore_id = "" },
      { id = "lxc/9203", node_name = "pve01", type = "lxc", vm_id = 9203, datastore_id = "" },
      { id = "qemu/9302", node_name = "pve01", type = "qemu", vm_id = 9302, datastore_id = "" },
      { id = "qemu/9303", node_name = "pve01", type = "qemu", vm_id = 9303, datastore_id = "" },
    ]
  }
}

override_data {
  target = module.template_source["vm-docker"].data.proxmox_virtual_environment_pool.templates
  values = {
    members = [
      { id = "lxc/9202", node_name = "pve01", type = "lxc", vm_id = 9202, datastore_id = "" },
      { id = "lxc/9203", node_name = "pve01", type = "lxc", vm_id = 9203, datastore_id = "" },
      { id = "qemu/9302", node_name = "pve01", type = "qemu", vm_id = 9302, datastore_id = "" },
      { id = "qemu/9303", node_name = "pve01", type = "qemu", vm_id = 9303, datastore_id = "" },
    ]
  }
}

override_data {
  target = module.template_source["lxc-runner"].data.proxmox_virtual_environment_containers.all
  values = {
    containers = [
      { name = "tmpl-lxc-runner-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v1", "previous"], template = true, vm_id = 9202 },
      { name = "tmpl-lxc-runner-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9203 },
    ]
  }
}

override_data {
  target = module.template_source["vm-docker"].data.proxmox_virtual_environment_vms.all
  values = {
    vms = [
      { name = "tmpl-vm-docker-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "vm-docker", "v1", "previous"], template = true, vm_id = 9302 },
      { name = "tmpl-vm-docker-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "vm-docker", "v2", "current"], template = true, vm_id = 9303 },
    ]
  }
}

variables {
  host                 = "pve01"
  probe_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE0000 r15-test"
}

run "clones_inherit_the_template_firewall_and_the_stack_declares_none_of_it" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : length(regexall("proxmox_virtual_environment_firewall_(rules|options)", file("${path.module}/${f}"))) == 0
    ])
    error_message = "The stack must not declare firewall rules or options for the clones: they inherit the template's, which is the runner-class policy R15 has to measure."
  }

  assert {
    condition     = length(regexall("resource \"proxmox_virtual_environment_firewall_ipset\" \"vm_ipfilter\"", file("${path.module}/main.tf"))) == 1
    error_message = "Templates carry no ipsets: the VM still needs ipfilter-net0 declared here."
  }
}

run "guests_are_unprivileged_onboot_and_filtered_on_the_guest_vnet" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.probe.unprivileged == true && proxmox_virtual_environment_container.probe.start_on_boot == true
    error_message = "The container must be unprivileged and start on boot."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.probe.on_boot == true
    error_message = "The VM must start on boot."
  }

  assert {
    condition     = proxmox_virtual_environment_container.probe.network_interface[0].firewall == true && proxmox_virtual_environment_container.probe.network_interface[0].bridge == "guests"
    error_message = "The container NIC must sit on vnet guests with the firewall flag, or no guest rule applies."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.probe.network_device[0].firewall == true && proxmox_virtual_environment_vm.probe.network_device[0].bridge == "guests"
    error_message = "The VM NIC must sit on vnet guests with the firewall flag, or no guest rule applies."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.probe.agent[0].enabled == false && proxmox_virtual_environment_vm.probe.stop_on_destroy == true
    error_message = "The cloud image has no guest agent: the VM must not wait for one."
  }
}

run "addresses_dns_and_ipfilter_follow_the_guest_subnet" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.probe.initialization[0].ip_config[0].ipv4[0].address == "10.99.16.21/24" && proxmox_virtual_environment_container.probe.initialization[0].ip_config[0].ipv4[0].gateway == "10.99.16.1"
    error_message = "The container must take the static address 10.99.16.21/24 behind gateway 10.99.16.1."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.probe.initialization[0].ip_config[0].ipv4[0].address == "10.99.16.22/24" && proxmox_virtual_environment_vm.probe.initialization[0].ip_config[0].ipv4[0].gateway == "10.99.16.1"
    error_message = "The VM must take the static address 10.99.16.22/24 behind gateway 10.99.16.1."
  }

  assert {
    condition     = proxmox_virtual_environment_container.probe.initialization[0].dns[0].servers == tolist(["1.1.1.1"]) && proxmox_virtual_environment_vm.probe.initialization[0].dns[0].servers == tolist(["1.1.1.1"])
    error_message = "Both guests must resolve through 1.1.1.1."
  }

  assert {
    condition     = one([for c in proxmox_virtual_environment_firewall_ipset.vm_ipfilter.cidr : c.name]) == "10.99.16.22" && proxmox_virtual_environment_firewall_ipset.vm_ipfilter.name == "ipfilter-net0"
    error_message = "ipfilter on a VM blocks everything unless ipfilter-net0 holds the VM's own address."
  }
}

run "a_private_key_is_rejected" {
  command = plan

  variables {
    probe_ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }

  expect_failures = [var.probe_ssh_public_key]
}

run "address_outside_the_host_subnet_is_rejected" {
  command = plan

  variables {
    host           = "example-pve02"
    inventory_file = "../proxmox-host/tests/fixtures/hosts.yml"
  }

  override_data {
    target = module.template_source["lxc-runner"].data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "tmpl-lxc-runner-v2", node_name = "example-pve02", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9203 },
      ]
    }
  }

  override_data {
    target = module.template_source["vm-docker"].data.proxmox_virtual_environment_vms.all
    values = {
      vms = [
        { name = "tmpl-vm-docker-v2", node_name = "example-pve02", status = "stopped", tags = ["homelab-template", "vm-docker", "v2", "current"], template = true, vm_id = 9303 },
      ]
    }
  }

  override_data {
    target = module.template_source["lxc-runner"].data.proxmox_virtual_environment_pool.templates
    values = {
      members = [
        { id = "lxc/9203", node_name = "example-pve02", type = "lxc", vm_id = 9203, datastore_id = "" },
        { id = "qemu/9303", node_name = "example-pve02", type = "qemu", vm_id = 9303, datastore_id = "" },
      ]
    }
  }

  override_data {
    target = module.template_source["vm-docker"].data.proxmox_virtual_environment_pool.templates
    values = {
      members = [
        { id = "lxc/9203", node_name = "example-pve02", type = "lxc", vm_id = 9203, datastore_id = "" },
        { id = "qemu/9303", node_name = "example-pve02", type = "qemu", vm_id = 9303, datastore_id = "" },
      ]
    }
  }

  expect_failures = [
    proxmox_virtual_environment_container.probe,
    proxmox_virtual_environment_vm.probe,
  ]
}

run "probe_clones_overwrite_the_inherited_template_tags" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.probe.tags == tolist(["r15-probe"]) && proxmox_virtual_environment_vm.probe.tags == tolist(["r15-probe"])
    error_message = "A linked clone inherits the template's tags, current included; the probe guests must overwrite them with r15-probe."
  }
}

run "guests_clone_linked_from_the_resolved_templates" {
  command = plan

  assert {
    condition     = one(proxmox_virtual_environment_container.probe.clone).vm_id == 9203 && one(proxmox_virtual_environment_container.probe.clone).full == false
    error_message = "The container must be a linked clone (full = false) of the lxc-runner template tagged current, VMID 9203."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.probe.clone).vm_id == 9303 && one(proxmox_virtual_environment_vm.probe.clone).full == false
    error_message = "The VM must be a linked clone (full = false) of the vm-docker template tagged current, VMID 9303."
  }

  assert {
    condition     = proxmox_virtual_environment_container.probe.pool_id == "homelab" && proxmox_virtual_environment_vm.probe.pool_id == "homelab"
    error_message = "Clones must land in pool homelab, never in the templates pool."
  }

  assert {
    condition     = length(proxmox_virtual_environment_container.probe.operating_system) == 0 && length(proxmox_virtual_environment_vm.probe.disk) == 1 && one(proxmox_virtual_environment_vm.probe.disk).import_from == null
    error_message = "A clone must not also name a downloaded image."
  }
}

run "a_pin_changes_the_clone_source" {
  command = plan

  variables {
    template_pins = { "lxc-runner" = 1, "vm-docker" = 1 }
  }

  assert {
    condition     = one(proxmox_virtual_environment_container.probe.clone).vm_id == 9202 && one(proxmox_virtual_environment_vm.probe.clone).vm_id == 9302
    error_message = "With pin 1 per class the clones must come from the v1 templates, 9202 and 9302, not from current."
  }
}

run "template_sources_output_reports_the_resolved_vmids" {
  command = plan

  assert {
    condition     = output.template_sources["lxc-runner"] == 9203 && output.template_sources["vm-docker"] == 9303
    error_message = "template_sources must report the resolved VMID per class."
  }
}

run "the_vm_clone_installs_the_probe_key_from_the_vendor_data_snippet" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.probe.initialization[0].vendor_data_file_id == "local:snippets/r15-probe-vendor.yaml"
    error_message = "The VM clone must reference the vendor-data snippet that the keygen step writes, or sshd stays sealed."
  }
}
