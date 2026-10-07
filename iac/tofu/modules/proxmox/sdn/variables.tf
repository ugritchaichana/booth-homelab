variable "zone" {
  description = "SDN zone id."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,7}$", var.zone))
    error_message = "zone must be 1 to 8 characters: a lowercase letter, then lowercase letters or digits."
  }
}

variable "vnet" {
  description = "SDN vnet id."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,7}$", var.vnet))
    error_message = "vnet must be 1 to 8 characters: a lowercase letter, then lowercase letters or digits."
  }
}

variable "nodes" {
  description = "Proxmox node names the zone is deployed on."
  type        = set(string)

  validation {
    condition     = length(var.nodes) > 0
    error_message = "nodes must name at least one Proxmox node."
  }
}

variable "cidr" {
  description = "Guest subnet in canonical IPv4 CIDR form."
  type        = string

  validation {
    condition = (
      can(cidrnetmask(var.cidr))
      && try(tonumber(split("/", var.cidr)[1]) >= 16 && tonumber(split("/", var.cidr)[1]) <= 28, false)
      && try(cidrhost(var.cidr, 0) == split("/", var.cidr)[0], false)
    )
    error_message = "cidr must be an IPv4 network address with a prefix length from /16 to /28."
  }

  validation {
    condition = !can(cidrnetmask(var.cidr)) || alltrue([
      for reserved in concat(["10.99.0.0/24"], var.reserved_cidrs) :
      !(cidrcontains(var.cidr, cidrhost(reserved, 0)) || cidrcontains(reserved, cidrhost(var.cidr, 0)))
    ])
    error_message = "cidr must not overlap the management network 10.99.0.0/24 or any entry of reserved_cidrs."
  }
}

variable "gateway" {
  description = "Gateway address on the vnet; the host-side address of the subnet."
  type        = string

  validation {
    condition = (
      try(cidrcontains(var.cidr, var.gateway), false)
      && try(var.gateway != cidrhost(var.cidr, 0), false)
    )
    error_message = "gateway must be an address inside cidr other than the network address."
  }
}

variable "reserved_cidrs" {
  description = "Further IPv4 ranges the guest subnet must not overlap, on top of the management network."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for reserved in var.reserved_cidrs : can(cidrnetmask(reserved))])
    error_message = "every reserved_cidrs entry must be an IPv4 CIDR."
  }
}
