mock_provider "proxmox" {}

variables {
  node  = "pve01"
  class = "lxc-runner"
}

override_data {
  target = data.proxmox_virtual_environment_pool.templates
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
  target = data.proxmox_virtual_environment_containers.all
  values = {
    containers = [
      { name = "tmpl-lxc-runner-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v1", "previous"], template = true, vm_id = 9202 },
      { name = "tmpl-lxc-runner-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9203 },
      { name = "r15-probe-lxc", node_name = "pve01", status = "running", tags = [], template = false, vm_id = 9101 },
    ]
  }
}

override_data {
  target = data.proxmox_virtual_environment_vms.all
  values = {
    vms = [
      { name = "tmpl-vm-docker-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "vm-docker", "v1", "previous"], template = true, vm_id = 9302 },
      { name = "tmpl-vm-docker-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "vm-docker", "v2", "current"], template = true, vm_id = 9303 },
    ]
  }
}

run "current_tag_selects_the_one_lxc_template" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  assert {
    condition     = output.vmid == 9203 && output.type == "lxc" && output.disk_gb == 8
    error_message = "The lxc-runner class must resolve to the template tagged current, VMID 9203."
  }
}

run "current_tag_selects_the_one_vm_template" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  variables {
    class = "vm-docker"
  }

  assert {
    condition     = output.vmid == 9303 && output.type == "qemu" && output.disk_gb == 20
    error_message = "The vm-docker class must resolve to the template tagged current, VMID 9303."
  }
}

run "a_pin_selects_its_version_and_overrides_current" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  variables {
    pin = 1
  }

  assert {
    condition     = output.vmid == 9202
    error_message = "Pin 1 must select the v1 template, 9202, although v2 carries current."
  }
}

run "a_pin_to_a_missing_version_fails_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  variables {
    pin = 7
  }

  expect_failures = [output.vmid]
}

run "zero_matches_fail_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "tmpl-lxc-runner-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v1", "previous"], template = true, vm_id = 9202 },
      ]
    }
  }

  expect_failures = [output.vmid]
}

run "two_matches_fail_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "tmpl-lxc-runner-v1", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v1", "current"], template = true, vm_id = 9202 },
        { name = "tmpl-lxc-runner-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9203 },
      ]
    }
  }

  expect_failures = [output.vmid]
}

run "current_tag_on_a_running_guest_fails_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "runner-17", node_name = "pve01", status = "running", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = false, vm_id = 9203 },
      ]
    }
  }

  expect_failures = [output.vmid]
}

run "a_template_outside_the_class_block_fails_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "tmpl-lxc-runner-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9303 },
      ]
    }
  }

  expect_failures = [output.vmid]
}

run "a_template_outside_the_templates_pool_fails_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_pool.templates
    values = {
      members = [
        { id = "lxc/9202", node_name = "pve01", type = "lxc", vm_id = 9202, datastore_id = "" },
      ]
    }
  }

  expect_failures = [output.vmid]
}

run "an_unknown_class_fails_closed" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  variables {
    class = "windows"
  }

  expect_failures = [output.vmid]
}

run "a_non_whole_pin_is_rejected" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  variables {
    pin = 1.5
  }

  expect_failures = [var.pin]
}

run "a_clone_outside_the_pool_carrying_the_template_tags_is_ignored" {
  command = plan

  module {
    source = "../../modules/proxmox/template-source"
  }

  override_data {
    target = data.proxmox_virtual_environment_containers.all
    values = {
      containers = [
        { name = "tmpl-lxc-runner-v2", node_name = "pve01", status = "stopped", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = true, vm_id = 9203 },
        { name = "r15-probe-lxc", node_name = "pve01", status = "running", tags = ["homelab-template", "lxc-runner", "v2", "current"], template = false, vm_id = 9101 },
      ]
    }
  }

  assert {
    condition     = output.vmid == 9203
    error_message = "A linked clone outside pool templates inherits the template tags and must never be a candidate or a second match."
  }
}
