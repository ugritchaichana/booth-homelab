run "every_catalog_entry_has_positive_integer_sizes" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "aws/t3.medium"
  }

  assert {
    condition     = length(output.flavors) > 0
    error_message = "the catalog must hold at least one entry."
  }

  assert {
    condition = alltrue([
      for size in values(output.flavors) :
      try(can(regex("^[0-9]+$", jsonencode(size.cores))) && size.cores > 0, false)
    ])
    error_message = "every catalog entry needs a positive integer cores: ${jsonencode([for name, size in output.flavors : name if !try(can(regex("^[0-9]+$", jsonencode(size.cores))) && size.cores > 0, false)])}"
  }

  assert {
    condition = alltrue([
      for size in values(output.flavors) :
      try(can(regex("^[0-9]+$", jsonencode(size.memory_mb))) && size.memory_mb > 0, false)
    ])
    error_message = "every catalog entry needs a positive integer memory_mb: ${jsonencode([for name, size in output.flavors : name if !try(can(regex("^[0-9]+$", jsonencode(size.memory_mb))) && size.memory_mb > 0, false)])}"
  }

  assert {
    condition = alltrue([
      for size in values(output.flavors) :
      try(can(regex("^[0-9]+$", jsonencode(size.disk_gb))) && size.disk_gb > 0, false)
    ])
    error_message = "every catalog entry needs a positive integer disk_gb: ${jsonencode([for name, size in output.flavors : name if !try(can(regex("^[0-9]+$", jsonencode(size.disk_gb))) && size.disk_gb > 0, false)])}"
  }
}

run "catalog_balloon_never_exceeds_memory" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "aws/t3.medium"
  }

  assert {
    condition = alltrue([
      for size in values(output.flavors) :
      !can(size.balloon_mb) || try(size.balloon_mb <= size.memory_mb, false)
    ])
    error_message = "balloon_mb must not exceed memory_mb: ${jsonencode([for name, size in output.flavors : name if can(size.balloon_mb) && !try(size.balloon_mb <= size.memory_mb, false)])}"
  }
}

run "aws_t3_medium_plans_two_cores_4096_mb_30_gb" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "aws/t3.medium"
  }

  assert {
    condition     = output.cores == 2
    error_message = "aws/t3.medium must plan 2 cores."
  }

  assert {
    condition     = output.memory_mb == 4096
    error_message = "aws/t3.medium must plan 4096 MB."
  }

  assert {
    condition     = output.disk_gb == 30
    error_message = "aws/t3.medium must plan a 30 GB disk."
  }

  assert {
    condition     = output.vm == { cores = 2, memory = 4096, balloon = 2048, disk_gb = 30 }
    error_message = "the vm object must carry cores 2, memory 4096, balloon 2048 and disk 30."
  }
}

run "container_has_no_balloon_and_zero_swap" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "aws/t3.medium"
  }

  assert {
    condition     = !contains(keys(output.container), "balloon")
    error_message = "an LXC container has no balloon option."
  }

  assert {
    condition     = output.container == { cores = 2, memory = 4096, swap = 0, disk_gb = 30 }
    error_message = "the container object must carry cores 2, memory 4096, swap 0 and disk 30."
  }
}

run "unknown_flavor_is_rejected" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "aws/t3.nonexistent"
  }

  expect_failures = [output.cores, output.memory_mb, output.disk_gb, output.vm, output.container]
}

run "malformed_flavor_is_rejected" {
  command = plan

  module {
    source = "../../modules/flavor"
  }

  variables {
    flavor = "t3.medium"
  }

  expect_failures = [var.flavor]
}
