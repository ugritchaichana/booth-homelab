variable "flavor" {
  description = "Flavor name as provider/instance, for example aws/t3.medium."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+/[^/[:space:]]+$", var.flavor))
    error_message = "flavor must be provider/instance with no spaces, for example aws/t3.medium."
  }
}

variable "catalog_path" {
  description = "Path to the flavor catalog JSON; null selects iac/tofu/flavors.json."
  type        = string
  default     = null
}
