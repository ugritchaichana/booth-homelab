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
