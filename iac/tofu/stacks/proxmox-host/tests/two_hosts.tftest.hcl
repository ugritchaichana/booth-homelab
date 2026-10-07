mock_provider "proxmox" {}

variables {
  inventory_file = "tests/fixtures/hosts.yml"
}

run "first_host_plans_its_subnet" {
  command = plan

  variables {
    host = "pve01"
  }

  assert {
    condition     = output.node_name == "pve01" && output.guest_network.cidr == "10.99.16.0/24"
    error_message = "pve01 must plan its own node and subnet."
  }
}

run "second_host_plans_with_no_code_change" {
  command = plan

  variables {
    host = "example-pve02"
  }

  assert {
    condition     = output.node_name == "example-pve02" && output.guest_network.cidr == "10.99.17.0/24"
    error_message = "example-pve02 must plan its own node and subnet from the inventory alone."
  }

  assert {
    condition     = output.guest_network.gateway == "10.99.17.1"
    error_message = "example-pve02 must plan its own gateway."
  }
}

run "unknown_host_is_rejected" {
  command = plan

  variables {
    host = "example-pve03"
  }

  expect_failures = [var.host]
}
