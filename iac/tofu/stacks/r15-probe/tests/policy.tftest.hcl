mock_provider "proxmox" {}

override_resource {
  target = proxmox_download_file.lxc_template
  values = {
    id = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
  }
}

override_resource {
  target = proxmox_download_file.image
  values = {
    id = "local:import/debian-13-genericcloud-amd64-20261001-2618.qcow2"
  }
}

variables {
  host                 = "pve01"
  probe_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLEEXAMPLE0000 r15-test"
}

run "both_guests_carry_the_runner_class_firewall_options" {
  command = plan

  assert {
    condition = alltrue([
      for options in [
        proxmox_virtual_environment_firewall_options.lxc,
        proxmox_virtual_environment_firewall_options.vm,
        ] : (
        options.enabled == true
        && options.input_policy == "DROP"
        && options.output_policy == "DROP"
        && options.ipfilter == true
        && options.log_level_out == "info"
        && options.macfilter == true
        && options.dhcp == false
        && options.radv == false
        && options.ndp == true
      )
    ])
    error_message = "Each probe guest must run the firewall with policy_in DROP, policy_out DROP, ipfilter on, log_level_out info, macfilter on, and dhcp, radv off."
  }

  assert {
    condition     = proxmox_virtual_environment_firewall_options.lxc.output_policy == "DROP" && proxmox_virtual_environment_firewall_options.vm.output_policy == "DROP"
    error_message = "Outbound policy DROP is what denies IPv6 egress: the security group holds IPv4 sets only."
  }
}

run "each_guest_has_the_control_rule_and_the_egress_group" {
  command = plan

  assert {
    condition = alltrue([
      for rules in [
        proxmox_virtual_environment_firewall_rules.lxc.rule,
        proxmox_virtual_environment_firewall_rules.vm.rule,
        ] : (
        length(rules) == 2
        && length([for r in rules : r if r.security_group == "guest-egress" && r.enabled]) == 1
        && length([for r in rules : r if r.type == "in" && r.action == "ACCEPT" && r.proto == "tcp" && r.dport == "22" && r.source == "10.99.16.1" && r.enabled]) == 1
      )
    ])
    error_message = "Each guest needs exactly two rules: security group guest-egress, and tcp/22 inbound from 10.99.16.1 only."
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

run "container_template_comes_from_the_official_mirror_with_its_checksum" {
  command = plan

  assert {
    condition     = proxmox_download_file.lxc_template.url == "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst" && proxmox_download_file.lxc_template.content_type == "vztmpl"
    error_message = "The container template must be downloaded as vztmpl from the official template mirror."
  }

  assert {
    condition     = proxmox_download_file.lxc_template.checksum_algorithm == "sha512" && proxmox_download_file.lxc_template.checksum == "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
    error_message = "The template download must carry the pinned SHA512."
  }

  assert {
    condition     = proxmox_virtual_environment_container.probe.operating_system[0].template_file_id == "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    error_message = "The container must use the downloaded template."
  }
}

run "image_is_pinned_to_a_dated_directory_with_its_checksum" {
  command = plan

  assert {
    condition     = proxmox_download_file.image.url == "https://cloud.debian.org/images/cloud/trixie/20261001-2618/debian-13-genericcloud-amd64-20261001-2618.qcow2" && proxmox_download_file.image.content_type == "import"
    error_message = "The image must come from a dated directory and use the import content type."
  }

  assert {
    condition     = proxmox_download_file.image.checksum_algorithm == "sha512" && length(proxmox_download_file.image.checksum) == 128
    error_message = "The image download must carry its SHA512 checksum."
  }
}

run "latest_directory_is_rejected" {
  command = plan

  variables {
    image_directory = "latest"
  }

  expect_failures = [var.image_directory]
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

  expect_failures = [
    proxmox_virtual_environment_container.probe,
    proxmox_virtual_environment_vm.probe,
  ]
}

run "no_tags_at_create_because_a_pool_scoped_token_cannot_inherit_them" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.probe.tags == null && proxmox_virtual_environment_vm.probe.tags == null
    error_message = "Tags are checked on /vms/<id> without the pool, so a pool-scoped token cannot set them at create time."
  }
}
