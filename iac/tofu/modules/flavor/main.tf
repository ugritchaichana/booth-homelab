locals {
  catalog = jsondecode(file(coalesce(var.catalog_path, "${path.module}/../../flavors.json")))

  flavors = merge([
    for provider, spec in local.catalog.providers : {
      for instance, size in spec.instances : "${provider}/${instance}" => size
    }
  ]...)

  size = lookup(local.flavors, var.flavor, null)

  unknown_flavor_message = "flavor ${var.flavor} is not in the catalog; use a provider/instance key of iac/tofu/flavors.json."
}
