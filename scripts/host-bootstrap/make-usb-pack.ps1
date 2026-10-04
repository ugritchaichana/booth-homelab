<#
.SYNOPSIS
    Packages the Host Bootstrap suite into a portable tar.gz / folder for USB transfer.
#>
param(
    [string]$TargetUsbDrive
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$outputArchive = Join-Path $scriptDir "..\..\pve-bootstrap-bundle.tar.gz"
$outputArchive = [System.IO.Path]::GetFullPath($outputArchive)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Packaging Host Bootstrap Suite for USB Flash Drive    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Ensure all shell scripts have LF endings
Write-Host "`n==> Step 1: Normalizing LF Line Endings for Linux..."
Get-ChildItem -Path $scriptDir -Filter "*.sh" | ForEach-Object {
    $content = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($_.FullName, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "    [LF] $($_.Name)" -ForegroundColor DarkGray
}

# 2. Create README for USB
$readmePath = Join-Path $scriptDir "README-BOOTSTRAP.txt"
$readmeContent = @"
================================================================================
  Acer Swift Go 14: Debian 12 -> Proxmox VE 8.x Host Bootstrap Suite
================================================================================

HOW TO RUN ON CLEAN DEBIAN 12 MINIMAL INSTALL:

1. Insert this USB drive into the Acer Swift Go 14 laptop.
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
"@
Set-Content -Path $readmePath -Value $readmeContent -Encoding UTF8

Write-Host "`n==> Step 2: Creating Portable Tarball: $outputArchive"
# Use tar (available on modern Windows)
tar -czf $outputArchive -C (Split-Path $scriptDir -Parent) "host-bootstrap"
Write-Host "    [PASS] Created: $outputArchive" -ForegroundColor Green

# 3. Optional copy to USB drive
if ($TargetUsbDrive) {
    if (Test-Path $TargetUsbDrive) {
        $dest = Join-Path $TargetUsbDrive "host-bootstrap"
        Write-Host "`n==> Step 3: Copying directly to USB Drive: $dest"
        Copy-Item -Path $scriptDir -Destination $dest -Recurse -Force
        Write-Host "    [PASS] Copied directly to USB!" -ForegroundColor Green
    } else {
        Write-Warning "Target USB drive '$TargetUsbDrive' not found."
    }
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   PACKAGING COMPLETE: Ready to transfer to Laptop!       " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
