================================================================================
  Baremetal Host: Debian 12 -> Proxmox VE 8.x Host Bootstrap Suite
================================================================================

HOW TO RUN ON CLEAN DEBIAN 12 MINIMAL INSTALL:

1. Insert this USB drive into the target baremetal node.
2. Mount the USB drive (as root):
     sudo mkdir -p /mnt/usb
     sudo mount /dev/sdb1 /mnt/usb    # (or check with: lsblk)
     cd /mnt/usb/host-bootstrap       # (or copy to ~/host-bootstrap)

3. Make scripts executable:
     chmod +x *.sh

4. Run Stage 1 (Hardware check, Repos, PVE 6.8+ Kernel):
     sudo ./bootstrap.sh --stage=1

5. Reboot the laptop when prompted:
     sudo reboot

6. After reboot, log back in and run Stage 2 (PVE Core, Routed NAT, Tailscale):
     cd /mnt/usb/host-bootstrap
     sudo ./bootstrap.sh --stage=2

7. Access Proxmox Web GUI via Tailscale:
     https://<YOUR_TAILSCALE_IP>:8006
================================================================================
