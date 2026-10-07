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
  target = module.template_source["lxc-runner-v1"].data.proxmox_virtual_environment_pool.templates
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
  target = module.template_source["lxc-runner-v1"].data.proxmox_virtual_environment_containers.all
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
  host           = "pve01"
  guests_file    = "tests/fixtures/guests.yml"
  inventory_file = "tests/fixtures/hosts.yml"
}

run "aws_t3_medium_sizes_both_template_classes" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].cpu[0].cores == 2 && proxmox_virtual_environment_container.guest["demo"].memory[0].dedicated == 4096 && proxmox_virtual_environment_container.guest["demo"].memory[0].swap == 0
    error_message = "The lxc-runner guest of flavor aws/t3.medium must plan 2 cores, 4096 MB and no swap."
  }

  assert {
    condition     = one(proxmox_virtual_environment_container.guest["demo"].disk).size == 30
    error_message = "The lxc-runner guest of flavor aws/t3.medium must plan a 30 GB disk."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.guest["smoke"].cpu[0].cores == 2 && proxmox_virtual_environment_vm.guest["smoke"].memory[0].dedicated == 4096 && proxmox_virtual_environment_vm.guest["smoke"].memory[0].floating == 2048
    error_message = "The vm-docker guest of flavor aws/t3.medium must plan 2 cores, 4096 MB and a 2048 MB balloon."
  }

  assert {
    condition     = one(proxmox_virtual_environment_vm.guest["smoke"].disk).size == 30
    error_message = "The vm-docker guest of flavor aws/t3.medium must plan a 30 GB disk."
  }
}

run "guests_carry_the_flavor_the_flavor_guest_and_the_source_tags" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].tags == tolist(["flavor-aws-t3.medium", "flavor-guest", "src-lxc-runner-v2"]) && proxmox_virtual_environment_vm.guest["smoke"].tags == tolist(["flavor-aws-t3.medium", "flavor-guest", "src-vm-docker-v2"])
    error_message = "Both guests must overwrite the inherited template tags with flavor-aws-t3.medium, flavor-guest and src-<class>-v2, sorted as Proxmox stores them."
  }
}

run "names_say_the_role_the_template_class_and_the_cloned_version" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].initialization[0].hostname == "demo-lxc-runner-v2" && proxmox_virtual_environment_vm.guest["smoke"].name == "smoke-vm-docker-v2"
    error_message = "Names must be <role>-<template class>-v<N> with N the version tagged current: demo-lxc-runner-v2 and smoke-vm-docker-v2."
  }

  assert {
    condition     = output.guests["demo"].name == "demo-lxc-runner-v2" && output.guests["smoke"].name == "smoke-vm-docker-v2"
    error_message = "The guests output must report the composed names."
  }
}

run "tag_is_proxmox_valid_for_a_mixed_case_flavor" {
  command = plan

  variables {
    host = "case-mixed-case-flavor"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.guest["azure-vm"].tags == tolist(["flavor-azure-standard_b2s", "flavor-guest", "src-vm-docker-v2"])
    error_message = "A flavor tag must be lowercase and use only a-z, 0-9, underscore, dot, plus and hyphen: Standard_B2s becomes flavor-azure-standard_b2s."
  }
}

run "guests_keep_the_firewall_and_network_the_guard_requires" {
  command = plan

  assert {
    condition = alltrue([
      for f in fileset(path.module, "*.tf") : length(regexall("proxmox_virtual_environment_firewall_(rules|options)", file("${path.module}/${f}"))) == 0
    ])
    error_message = "The stack must not declare firewall rules or options: clones inherit the template's runner-class policy."
  }

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].unprivileged == true && proxmox_virtual_environment_container.guest["demo"].network_interface[0].firewall == true && proxmox_virtual_environment_container.guest["demo"].network_interface[0].bridge == "guests"
    error_message = "The container must be unprivileged and its NIC must sit on vnet guests with the firewall flag."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.guest["smoke"].network_device[0].firewall == true && proxmox_virtual_environment_vm.guest["smoke"].network_device[0].bridge == "guests"
    error_message = "The VM NIC must sit on vnet guests with the firewall flag."
  }

  assert {
    condition     = one([for c in proxmox_virtual_environment_firewall_ipset.vm_ipfilter["smoke"].cidr : c.name]) == "10.99.16.102" && proxmox_virtual_environment_firewall_ipset.vm_ipfilter["smoke"].name == "ipfilter-net0"
    error_message = "ipfilter on a VM blocks everything unless ipfilter-net0 holds the VM's own address."
  }

  assert {
    condition     = length(proxmox_virtual_environment_firewall_ipset.vm_ipfilter) == 1
    error_message = "Only the VM guest gets an ipset."
  }
}

run "guests_are_linked_clones_in_the_homelab_pool_and_stay_stopped" {
  command = plan

  assert {
    condition     = one(proxmox_virtual_environment_container.guest["demo"].clone).vm_id == 9203 && one(proxmox_virtual_environment_container.guest["demo"].clone).full == false && one(proxmox_virtual_environment_vm.guest["smoke"].clone).vm_id == 9303 && one(proxmox_virtual_environment_vm.guest["smoke"].clone).full == false
    error_message = "Guests must be linked clones of the templates tagged current, 9203 and 9303."
  }

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].pool_id == "homelab" && proxmox_virtual_environment_vm.guest["smoke"].pool_id == "homelab"
    error_message = "Guests must land in pool homelab."
  }

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].started == false && proxmox_virtual_environment_vm.guest["smoke"].started == false && proxmox_virtual_environment_container.guest["demo"].start_on_boot == true && proxmox_virtual_environment_vm.guest["smoke"].on_boot == true
    error_message = "Guests are created stopped and start on boot."
  }
}

run "two_guests_get_distinct_addresses_and_vm_ids_clear_of_the_probes" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].initialization[0].ip_config[0].ipv4[0].address == "10.99.16.101/24" && proxmox_virtual_environment_vm.guest["smoke"].initialization[0].ip_config[0].ipv4[0].address == "10.99.16.102/24"
    error_message = "Slots 1 and 2 must plan 10.99.16.101/24 and 10.99.16.102/24."
  }

  assert {
    condition     = proxmox_virtual_environment_container.guest["demo"].initialization[0].ip_config[0].ipv4[0].gateway == "10.99.16.1" && proxmox_virtual_environment_vm.guest["smoke"].initialization[0].ip_config[0].ipv4[0].gateway == "10.99.16.1"
    error_message = "Both guests must route through gateway 10.99.16.1."
  }

  assert {
    condition     = length(distinct([for g in values(output.guests) : g.address])) == 2 && length(distinct([for g in values(output.guests) : g.vm_id])) == 2
    error_message = "Two guests must never share an address or a VMID."
  }

  assert {
    condition     = length(setintersection(toset([for g in values(output.guests) : g.address]), toset(["10.99.16.1", "10.99.16.21", "10.99.16.22", "10.99.16.30", "10.99.16.31"]))) == 0 && length(setintersection(toset([for g in values(output.guests) : g.vm_id]), toset([9050, 9101, 9102]))) == 0
    error_message = "Guest addresses and VMIDs must stay clear of the gateway, the probes and the template build addresses."
  }
}

run "only_the_selected_hosts_guests_are_planned" {
  command = plan

  assert {
    condition     = toset(keys(output.guests)) == toset(["demo", "smoke"])
    error_message = "A guest listed under another host must not be planned on pve01."
  }
}

run "an_empty_guest_list_plans_nothing" {
  command = plan

  variables {
    guests_file = null
  }

  assert {
    condition     = length(output.guests) == 0
    error_message = "The shipped guests.yml must plan no guest until one is added."
  }
}

run "a_pin_selects_that_template_version" {
  command = plan

  variables {
    host = "case-pinned"
  }

  assert {
    condition     = one(proxmox_virtual_environment_container.guest["pinned-lxc"].clone).vm_id == 9202
    error_message = "template_version 1 must clone the v1 template, 9202, not the one tagged current."
  }

  assert {
    condition     = proxmox_virtual_environment_container.guest["pinned-lxc"].initialization[0].hostname == "pinned-lxc-lxc-runner-v1" && contains(proxmox_virtual_environment_container.guest["pinned-lxc"].tags, "src-lxc-runner-v1")
    error_message = "A guest pinned to v1 must be named and tagged with v1, not with the current version."
  }
}

run "unknown_flavor_is_rejected" {
  command = plan

  variables {
    host = "case-unknown-flavor"
  }

  expect_failures = [output.guests]
}

run "malformed_flavor_is_rejected" {
  command = plan

  variables {
    host = "case-malformed-flavor"
  }

  expect_failures = [output.guests]
}

run "flavor_with_more_cores_than_the_host_budget_is_rejected" {
  command = plan

  variables {
    guest_budget = { cores = 1, memory_mb = 20480, disk_gb = 128 }
  }

  expect_failures = [
    proxmox_virtual_environment_container.guest["demo"],
    proxmox_virtual_environment_vm.guest["smoke"],
  ]
}

run "flavor_with_more_memory_than_the_host_budget_is_rejected" {
  command = plan

  variables {
    guest_budget = { cores = 12, memory_mb = 2048, disk_gb = 128 }
  }

  expect_failures = [
    proxmox_virtual_environment_container.guest["demo"],
    proxmox_virtual_environment_vm.guest["smoke"],
  ]
}

run "flavor_with_more_disk_than_the_host_budget_is_rejected" {
  command = plan

  variables {
    guest_budget = { cores = 12, memory_mb = 20480, disk_gb = 29 }
  }

  expect_failures = [
    proxmox_virtual_environment_container.guest["demo"],
    proxmox_virtual_environment_vm.guest["smoke"],
  ]
}

run "flavor_exactly_at_the_host_budget_is_accepted" {
  command = plan

  variables {
    guest_budget = { cores = 2, memory_mb = 4096, disk_gb = 30 }
  }

  assert {
    condition     = length(output.guests) == 2
    error_message = "A flavor equal to the budget on every axis must plan."
  }
}

run "flavor_disk_smaller_than_the_vm_template_disk_is_rejected" {
  command = plan

  variables {
    host = "case-small-disk-vm"
  }

  expect_failures = [proxmox_virtual_environment_vm.guest["small-vm"]]
}

run "flavor_disk_larger_than_the_container_template_disk_is_accepted" {
  command = plan

  variables {
    host = "case-small-disk-lxc"
  }

  assert {
    condition     = one(proxmox_virtual_environment_container.guest["small-lxc"].disk).size == 10
    error_message = "aws/t3.nano is 10 GB and the lxc-runner template 8 GB, so the guest must plan a 10 GB disk."
  }
}

run "two_guests_with_one_slot_are_rejected" {
  command = plan

  variables {
    host = "case-duplicate-slot"
  }

  expect_failures = [output.guests]
}

run "slot_outside_one_to_ninety_nine_is_rejected" {
  command = plan

  variables {
    host = "case-slot-out-of-range"
  }

  expect_failures = [output.guests]
}

run "unknown_template_class_is_rejected" {
  command = plan

  variables {
    host = "case-bad-class"
  }

  expect_failures = [output.guests]
}

run "guest_name_that_is_not_a_hostname_is_rejected" {
  command = plan

  variables {
    host = "case-bad-name"
  }

  expect_failures = [output.guests]
}

run "role_that_makes_the_name_longer_than_63_characters_is_rejected" {
  command = plan

  variables {
    host = "case-role-too-long"
  }

  expect_failures = [output.guests]
}

run "role_that_makes_the_name_exactly_63_characters_is_accepted" {
  command = plan

  variables {
    host = "case-role-at-the-limit"
  }

  assert {
    condition     = length(one(values(output.guests)).name) == 63
    error_message = "A role of 49 characters composes a 63-character name, which is a valid hostname."
  }
}
