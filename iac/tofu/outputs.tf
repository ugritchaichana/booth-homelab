output "cloud_provider" {
  description = "Active cloud provider abstraction"
  value       = var.cloud_provider
}

output "resolved_flavors" {
  description = "Hardware specs resolved for each component based on cloud catalog"
  value = {
    runner_dotnet = {
      flavor = var.runner_dotnet_flavor
      specs  = local.dotnet_specs
    }
    runner_angular = {
      flavor = var.runner_angular_flavor
      specs  = local.angular_specs
    }
    minio_cache = {
      flavor = var.minio_cache_flavor
      specs  = local.minio_specs
    }
  }
}

output "containers" {
  description = "Deployed container details"
  value = {
    runner_dotnet  = module.runner_dotnet
    runner_angular = module.runner_angular
    minio_cache    = module.minio_cache
  }
}
