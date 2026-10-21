mock_provider "proxmox" {}

variables {
  host            = "pve01"
  inventory_file  = "tests/fixtures/hosts.yml"
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE0000 sim-cache-test"]
}

run "container_sits_on_the_cache_vnet_beside_the_build_cache_with_its_own_id_and_address" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.vm_id == 9051 && proxmox_virtual_environment_container.sim_cache.pool_id == "homelab"
    error_message = "The sim cache container must be 9051 in pool homelab, next to the build cache at 9050."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.unprivileged == true && proxmox_virtual_environment_container.sim_cache.start_on_boot == true
    error_message = "The sim cache container must be unprivileged and start on boot."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.started == false && length(regexall("ignore_changes = [[]started[]]", file("${path.module}/main.tf"))) == 1
    error_message = "The container must be created stopped and never be stopped later: the playbook starts it only after the firewall read-back."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.network_interface[0].bridge == "cache" && proxmox_virtual_environment_container.sim_cache.network_interface[0].firewall == true && length(proxmox_virtual_environment_container.sim_cache.network_interface) == 1
    error_message = "One NIC on vnet cache with the firewall flag, or no guest rule applies and the guard stops the guest."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.initialization[0].ip_config[0].ipv4[0].address == "10.99.17.11/24" && proxmox_virtual_environment_container.sim_cache.initialization[0].ip_config[0].ipv4[0].gateway == "10.99.17.1"
    error_message = "The container must take 10.99.17.11/24 behind gateway 10.99.17.1."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.cpu[0].cores == 1 && proxmox_virtual_environment_container.sim_cache.memory[0].dedicated == 1536 && proxmox_virtual_environment_container.sim_cache.disk[0].size == 4
    error_message = "The container must have 1 core, 1536 MB and a 4 GiB root disk."
  }
}

run "data_volume_is_ten_gib_at_the_service_path" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.mount_point[0].size == "10G" && proxmox_virtual_environment_container.sim_cache.mount_point[0].path == "/var/lib/sim-cache" && proxmox_virtual_environment_container.sim_cache.mount_point[0].volume == "local-lvm"
    error_message = "mp0 must be 10G of local-lvm at /var/lib/sim-cache."
  }
}

run "vm_id_stays_outside_the_template_blocks_and_probe_ids" {
  command = plan

  assert {
    condition     = !contains(local.reserved_vm_ids, 9051) && contains(local.reserved_vm_ids, 9200) && contains(local.reserved_vm_ids, 9399) && contains(local.reserved_vm_ids, 9101) && contains(local.reserved_vm_ids, 9102)
    error_message = "The reserved set must cover 9200 to 9399 and the probe ids, and not 9051."
  }
}

run "firewall_options_are_the_runner_class_values" {
  command = plan

  assert {
    condition = (
      proxmox_virtual_environment_firewall_options.sim_cache.enabled == true
      && proxmox_virtual_environment_firewall_options.sim_cache.input_policy == "DROP"
      && proxmox_virtual_environment_firewall_options.sim_cache.output_policy == "DROP"
      && proxmox_virtual_environment_firewall_options.sim_cache.ipfilter == true
      && proxmox_virtual_environment_firewall_options.sim_cache.macfilter == true
      && proxmox_virtual_environment_firewall_options.sim_cache.dhcp == false
      && proxmox_virtual_environment_firewall_options.sim_cache.radv == false
    )
    error_message = "The guest firewall options must be the runner-class policy: enabled, DROP in and out, ipfilter and macfilter on, dhcp and radv off."
  }
}

run "rules_are_exactly_the_two_groups_the_build_cache_carries" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_firewall_rules.sim_cache.rule) == 2
    error_message = "The guest must carry exactly two rules, or the guard stops it."
  }

  assert {
    condition     = [for r in proxmox_virtual_environment_firewall_rules.sim_cache.rule : r.security_group] == ["guest-egress", "cache-ingress"]
    error_message = "The two rules must be the groups guest-egress and cache-ingress, the set the guard requires on the cache vnet."
  }
}

run "a_private_key_is_rejected" {
  command = plan

  variables {
    ssh_public_keys = ["-----BEGIN OPENSSH PRIVATE KEY-----"]
  }

  expect_failures = [var.ssh_public_keys]
}

run "a_vm_id_inside_a_template_block_is_rejected" {
  command = plan

  variables {
    vm_id = 9250
  }

  expect_failures = [var.vm_id]
}

run "a_host_without_the_sim_keys_fails_closed" {
  command = plan

  variables {
    host = "no-sim-keys"
  }

  expect_failures = [proxmox_virtual_environment_container.sim_cache]
}

run "the_gateway_address_is_rejected" {
  command = plan

  variables {
    host = "gateway-address"
  }

  expect_failures = [proxmox_virtual_environment_container.sim_cache]
}

run "the_build_cache_address_is_rejected" {
  command = plan

  variables {
    host = "build-cache-address"
  }

  expect_failures = [proxmox_virtual_environment_container.sim_cache]
}

run "name_and_tags_say_the_role_and_the_base_image" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.initialization[0].hostname == "sim-cache"
    error_message = "The hostname must be sim-cache."
  }

  assert {
    condition     = proxmox_virtual_environment_container.sim_cache.tags == tolist(["sim-cache", "src-debian-13"])
    error_message = "The tags must be sim-cache and src-<os image slug>, sorted as Proxmox stores them."
  }

  assert {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", local.hostname)) && length(local.hostname) <= 63
    error_message = "The hostname must be a valid DNS label of at most 63 characters."
  }
}
