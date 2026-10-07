mock_provider "proxmox" {}

variables {
  host            = "pve01"
  inventory_file  = "tests/fixtures/hosts.yml"
  ssh_public_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE0000 cache-test"]
}

run "container_sits_on_the_cache_vnet_with_the_planned_shape" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.cache.vm_id == 9050 && proxmox_virtual_environment_container.cache.pool_id == "homelab"
    error_message = "The cache container must be 9050 in pool homelab."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.unprivileged == true && proxmox_virtual_environment_container.cache.start_on_boot == true
    error_message = "The cache container must be unprivileged and start on boot."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.started == false && length(regexall("ignore_changes = [[]started[]]", file("${path.module}/main.tf"))) == 1
    error_message = "The container must be created stopped and never be stopped later: the playbook starts it only after the firewall read-back."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.network_interface[0].bridge == "cache" && proxmox_virtual_environment_container.cache.network_interface[0].firewall == true
    error_message = "The NIC must sit on vnet cache with the firewall flag, or no guest rule applies."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.initialization[0].ip_config[0].ipv4[0].address == "10.99.17.10/24" && proxmox_virtual_environment_container.cache.initialization[0].ip_config[0].ipv4[0].gateway == "10.99.17.1"
    error_message = "The container must take 10.99.17.10/24 behind gateway 10.99.17.1."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.cpu[0].cores == 1 && proxmox_virtual_environment_container.cache.memory[0].dedicated == 1024 && proxmox_virtual_environment_container.cache.disk[0].size == 4
    error_message = "The container must have 1 core, 1024 MB and a 4 GiB root disk."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.operating_system[0].template_file_id == "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    error_message = "The container must be built from the Debian 13 standard template the template role fetches."
  }
}

run "data_volume_is_ten_gib_at_the_service_path_and_the_cache_limit_fits_it" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.cache.mount_point[0].size == "10G" && proxmox_virtual_environment_container.cache.mount_point[0].path == "/var/lib/bazel-remote" && proxmox_virtual_environment_container.cache.mount_point[0].volume == "local-lvm"
    error_message = "mp0 must be 10G of local-lvm at /var/lib/bazel-remote."
  }

  assert {
    condition     = var.data_disk_gb <= 10 && local.max_size_gib * 10 <= var.data_disk_gb * 8
    error_message = "The cache limit read from the role defaults must stay within 80 percent of a data volume of at most 10 GiB."
  }

  assert {
    condition     = local.max_size_gib == 8
    error_message = "The role default cache_service_max_size_gib must read 8."
  }
}

run "vm_id_stays_outside_the_template_blocks_and_probe_ids" {
  command = plan

  assert {
    condition     = !contains(local.reserved_vm_ids, 9050) && contains(local.reserved_vm_ids, 9200) && contains(local.reserved_vm_ids, 9399) && contains(local.reserved_vm_ids, 9101) && contains(local.reserved_vm_ids, 9102) && !contains(local.reserved_vm_ids, 9400)
    error_message = "The reserved set must cover 9200 to 9399 and the probe ids 9101 and 9102, and not 9050."
  }
}

run "firewall_options_are_the_runner_class_values" {
  command = plan

  assert {
    condition = (
      proxmox_virtual_environment_firewall_options.cache.enabled == true
      && proxmox_virtual_environment_firewall_options.cache.input_policy == "DROP"
      && proxmox_virtual_environment_firewall_options.cache.output_policy == "DROP"
      && proxmox_virtual_environment_firewall_options.cache.ipfilter == true
      && proxmox_virtual_environment_firewall_options.cache.macfilter == true
      && proxmox_virtual_environment_firewall_options.cache.dhcp == false
      && proxmox_virtual_environment_firewall_options.cache.radv == false
    )
    error_message = "The guest firewall options must be the runner-class policy: enabled, DROP in and out, ipfilter and macfilter on, dhcp and radv off."
  }
}

run "rules_are_exactly_the_two_groups" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_firewall_rules.cache.rule) == 2
    error_message = "The guest must carry exactly two rules."
  }

  assert {
    condition     = [for r in proxmox_virtual_environment_firewall_rules.cache.rule : r.security_group] == ["guest-egress", "cache-ingress"]
    error_message = "The two rules must be the groups guest-egress and cache-ingress."
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

run "a_data_volume_the_cache_limit_does_not_fit_is_rejected" {
  command = plan

  variables {
    data_disk_gb = 8
  }

  expect_failures = [proxmox_virtual_environment_container.cache]
}

run "a_host_without_cache_keys_fails_closed" {
  command = plan

  variables {
    host = "no-cache-keys"
  }

  expect_failures = [proxmox_virtual_environment_container.cache]
}

run "the_gateway_address_is_rejected" {
  command = plan

  variables {
    host = "gateway-address"
  }

  expect_failures = [proxmox_virtual_environment_container.cache]
}

run "name_and_tags_say_the_role_and_the_base_image" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.cache.initialization[0].hostname == "build-cache-debian-13"
    error_message = "The hostname must be build-cache-<os image slug>, build-cache-debian-13 for the lxc-runner base image."
  }

  assert {
    condition     = proxmox_virtual_environment_container.cache.tags == tolist(["build-cache", "src-debian-13"])
    error_message = "The tags must be build-cache and src-<os image slug>, sorted as Proxmox stores them."
  }

  assert {
    condition     = local.image_slug == "debian-13" && strcontains(local.template_file, local.image_slug)
    error_message = "The slug must be read from the base image file name of the lxc-runner class."
  }

  assert {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", local.hostname)) && length(local.hostname) <= 63
    error_message = "The hostname must be a valid DNS label of at most 63 characters."
  }
}
