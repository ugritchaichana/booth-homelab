# ==============================================================================
# Proxmox MinIO S3 Remote Cache LXC Resource (bpg/proxmox)
# ==============================================================================

resource "proxmox_virtual_environment_container" "this" {
  node_name    = var.node_name
  vm_id        = var.vm_id
  description  = "High-Speed S3 Remote Cache (Alpine Linux / MinIO Engine)"
  tags         = ["s3-cache", "storage", "minio"]
  unprivileged = true

  start_on_boot = true

  startup {
    order      = 1
    up_delay   = 30
    down_delay = 15
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
    swap      = 512
  }

  disk {
    datastore_id = var.storage_pool
    size         = var.disk_size_gb
  }

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }

    user_account {
      keys = var.ssh_public_key != "" ? [var.ssh_public_key] : []
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  operating_system {
    template_file_id = var.template_file
    type             = "alpine"
  }
}
