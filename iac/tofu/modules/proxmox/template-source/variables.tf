variable "node" {
  description = "Proxmox node whose templates are searched."
  type        = string
}

variable "class" {
  description = "Template class: a key of pve_templates_classes in the classes file."
  type        = string
}

variable "pin" {
  description = "Template version N to use instead of the guest tagged current; null follows the current tag. A set pin wins over the tag (ADR 0044)."
  type        = number
  default     = null

  validation {
    condition     = var.pin == null ? true : (var.pin >= 1 && floor(var.pin) == var.pin)
    error_message = "pin must be null or a whole number of at least 1."
  }
}

variable "pool_id" {
  description = "Pool a template must be a member of."
  type        = string
  default     = "templates"
}

variable "classes_file" {
  description = "YAML file holding pve_templates_classes and pve_templates_marker_tag; null reads the Ansible role defaults, which also drive the build."
  type        = string
  default     = null
}
