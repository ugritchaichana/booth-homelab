terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.115.0"
    }
  }
}

resource "proxmox_sdn_zone_simple" "this" {
  id    = var.zone
  nodes = var.nodes

  depends_on = [proxmox_sdn_applier.finalizer]
}

resource "proxmox_sdn_vnet" "this" {
  id            = var.vnet
  zone          = proxmox_sdn_zone_simple.this.id
  isolate_ports = true
}

resource "proxmox_sdn_subnet" "this" {
  cidr    = var.cidr
  vnet    = proxmox_sdn_vnet.this.id
  gateway = var.gateway
  snat    = true
}

resource "proxmox_sdn_vnet" "additional" {
  for_each = var.additional_vnets

  id            = each.key
  zone          = proxmox_sdn_zone_simple.this.id
  isolate_ports = true
}

resource "proxmox_sdn_subnet" "additional" {
  for_each = var.additional_vnets

  cidr    = each.value.cidr
  vnet    = proxmox_sdn_vnet.additional[each.key].id
  gateway = each.value.gateway
  snat    = true
}

# Experimental provider resource: replaced on every SDN change so PVE applies the pending config.
resource "proxmox_sdn_applier" "this" {
  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_simple.this,
      proxmox_sdn_vnet.this,
      proxmox_sdn_subnet.this,
      proxmox_sdn_vnet.additional,
      proxmox_sdn_subnet.additional,
    ]
  }

  depends_on = [
    proxmox_sdn_zone_simple.this,
    proxmox_sdn_vnet.this,
    proxmox_sdn_subnet.this,
    proxmox_sdn_vnet.additional,
    proxmox_sdn_subnet.additional,
  ]
}

# Destroyed after the SDN objects, so deleting them is applied too.
resource "proxmox_sdn_applier" "finalizer" {
  on_create = false
}
