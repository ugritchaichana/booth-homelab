mock_provider "proxmox" {}

variables {
  host = "pve01"
}

run "pve01_plans_the_inventory_guest_network" {
  command = plan

  assert {
    condition     = module.guest_network.zone == "hlab" && module.guest_network.vnet == "guests"
    error_message = "pve01 must plan zone hlab and vnet guests."
  }

  assert {
    condition     = module.guest_network.cidr == "10.99.16.0/24" && module.guest_network.gateway == "10.99.16.1"
    error_message = "pve01 must plan subnet 10.99.16.0/24 with gateway 10.99.16.1."
  }
}

run "pve01_plans_the_cache_network" {
  command = plan

  assert {
    condition     = output.cache_network.vnet == "cache" && output.cache_network.cidr == "10.99.17.0/24" && output.cache_network.gateway == "10.99.17.1"
    error_message = "pve01 must plan vnet cache with subnet 10.99.17.0/24 and gateway 10.99.17.1."
  }
}

run "host_without_cache_network_plans_no_second_vnet" {
  command = plan

  variables {
    inventory_file = "tests/fixtures/hosts.yml"
    host           = "example-pve02"
  }

  assert {
    condition     = output.cache_network == null && length(module.guest_network.additional_vnets) == 0
    error_message = "a host with no cache_network must plan only the guest vnet."
  }
}

run "sdn_policy" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.16.0/24"
    gateway = "10.99.16.1"
  }

  assert {
    condition     = proxmox_sdn_vnet.this.isolate_ports == true
    error_message = "the vnet must isolate ports."
  }

  assert {
    condition     = proxmox_sdn_subnet.this.snat == true
    error_message = "the subnet must use SNAT."
  }

  assert {
    condition     = proxmox_sdn_subnet.this.dhcp_range == null && proxmox_sdn_zone_simple.this.dhcp == null
    error_message = "no DHCP range and no DHCP backend: guests use static addresses."
  }

  assert {
    condition     = proxmox_sdn_zone_simple.this.nodes == toset(["pve01"]) && proxmox_sdn_vnet.this.zone == "hlab"
    error_message = "the zone must be deployed on the host's node and carry the vnet."
  }

  assert {
    condition     = proxmox_sdn_subnet.this.vnet == "guests" && proxmox_sdn_subnet.this.gateway == "10.99.16.1"
    error_message = "the subnet must sit on the vnet with the inventory gateway."
  }
}

run "two_vnets_are_isolated_and_source_nated" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.16.0/24"
    gateway = "10.99.16.1"
    additional_vnets = {
      cache = { cidr = "10.99.17.0/24", gateway = "10.99.17.1" }
    }
  }

  assert {
    condition     = proxmox_sdn_vnet.this.id == "guests" && proxmox_sdn_vnet.this.isolate_ports == true && proxmox_sdn_subnet.this.cidr == "10.99.16.0/24" && proxmox_sdn_subnet.this.gateway == "10.99.16.1" && proxmox_sdn_subnet.this.snat == true
    error_message = "the guests vnet and subnet must keep isolate_ports, cidr, gateway and snat."
  }

  assert {
    condition     = proxmox_sdn_vnet.additional["cache"].isolate_ports == true && proxmox_sdn_vnet.additional["cache"].zone == "hlab"
    error_message = "the cache vnet must sit in the same zone and isolate ports."
  }

  assert {
    condition     = proxmox_sdn_subnet.additional["cache"].cidr == "10.99.17.0/24" && proxmox_sdn_subnet.additional["cache"].gateway == "10.99.17.1" && proxmox_sdn_subnet.additional["cache"].snat == true && proxmox_sdn_subnet.additional["cache"].vnet == "cache"
    error_message = "the cache subnet must be 10.99.17.0/24 with gateway 10.99.17.1, SNAT on, on vnet cache."
  }
}

run "additional_vnet_overlapping_the_first_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.16.0/24"
    gateway = "10.99.16.1"
    additional_vnets = {
      cache = { cidr = "10.99.16.0/25", gateway = "10.99.16.1" }
    }
  }

  expect_failures = [var.additional_vnets]
}

run "overlap_with_management_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.0.0/24"
    gateway = "10.99.0.1"
  }

  expect_failures = [var.cidr]
}

run "supernet_of_management_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.0.0/16"
    gateway = "10.99.16.1"
  }

  expect_failures = [var.cidr]
}

run "overlap_with_reserved_range_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone           = "hlab"
    vnet           = "guests"
    nodes          = ["pve01"]
    cidr           = "10.99.16.0/24"
    gateway        = "10.99.16.1"
    reserved_cidrs = ["10.99.16.128/25"]
  }

  expect_failures = [var.cidr]
}

run "prefix_longer_than_28_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.16.0/29"
    gateway = "10.99.16.1"
  }

  expect_failures = [var.cidr]
}

run "gateway_outside_the_subnet_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/sdn"
  }

  variables {
    zone    = "hlab"
    vnet    = "guests"
    nodes   = ["pve01"]
    cidr    = "10.99.16.0/24"
    gateway = "10.99.17.1"
  }

  expect_failures = [var.gateway]
}
