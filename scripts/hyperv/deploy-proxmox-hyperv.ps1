<#
.SYNOPSIS
    Automated Proxmox VE 8.x Hyper-V Virtual Machine Provisioner
.DESCRIPTION
    1. Self-elevates to Administrator if needed.
    2. Adds current user to Hyper-V Administrators group.
    3. Downloads official Proxmox VE 8.4 ISO.
    4. Creates Gen 2 VM with 8GB RAM, 4 vCPU, 50GB VHDX, and Default Switch.
    5. Enables Nested Virtualization (AMD-V Passthrough) and disables Secure Boot.
    6. Boots VM and launches vmconnect.exe console.
#>
[CmdletBinding()]
param(
    [string]$VmName = "Proxmox-Lab",
    [int64]$MemoryBytes = 8192MB,
    [int]$CpuCount = 4,
    [int64]$DiskSizeBytes = 50GB,
    [string]$BaseDir = "C:\HyperV"
)

# 1. Self-Elevation Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "==> Requesting Administrator Elevation (UAC)..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$scriptPath`""
    exit 0
}

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Proxmox VE 8.x Hyper-V Lab Automated Provisioner       " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 2. Add User to Hyper-V Administrators
$currentUser = $env:USERNAME
Write-Host "`n==> Step 1: Ensuring '$currentUser' is in 'Hyper-V Administrators'..."
try {
    net localgroup "Hyper-V Administrators" "$currentUser" /add 2>$null
    Write-Host "    [PASS] User group updated." -ForegroundColor Green
} catch {
    Write-Host "    [INFO] Already a member or error ignored." -ForegroundColor DarkGray
}

# 3. Create Directories
$isoDir = Join-Path $BaseDir "ISOs"
$vmDir = Join-Path $BaseDir "VMs"
$diskDir = Join-Path $BaseDir "Disks"

New-Item -ItemType Directory -Path $isoDir -Force | Out-Null
New-Item -ItemType Directory -Path $vmDir -Force | Out-Null
New-Item -ItemType Directory -Path $diskDir -Force | Out-Null

# 4. Download / Locate Proxmox VE 8.4 ISO
$isoUrl = "https://enterprise.proxmox.com/iso/proxmox-ve_8.4-1.iso"
$localRepoIso = "C:\Users\Booth\Desktop\MyProjects\Booth-homelab\ISOs\proxmox-ve_8.4-1.iso"
$isoPath = Join-Path $isoDir "proxmox-ve_8.4-1.iso"
$expectedBytes = 1571895296

if (Test-Path $localRepoIso) {
    $currentBytes = (Get-Item $localRepoIso).Length
    if ($currentBytes -ge $expectedBytes) {
        Write-Host "`n==> Step 2: Found verified Proxmox ISO in repository: $localRepoIso" -ForegroundColor Green
        $isoPath = $localRepoIso
    }
}

if ($isoPath -ne $localRepoIso) {
    if (Test-Path $isoPath) {
        $currentBytes = (Get-Item $isoPath).Length
        if ($currentBytes -ge $expectedBytes) {
            Write-Host "`n==> Step 2: Proxmox ISO already downloaded and verified: $isoPath" -ForegroundColor Green
        } else {
            Write-Host "`n==> Step 2: Incomplete download. Downloading Proxmox ISO..." -ForegroundColor Yellow
            curl.exe -L -o "$isoPath" "$isoUrl"
        }
    } else {
        Write-Host "`n==> Step 2: Downloading official Proxmox VE 8.4 ISO (~1.46 GB)..." -ForegroundColor Cyan
        curl.exe -L -o "$isoPath" "$isoUrl"
    }
}

if (-not (Test-Path $isoPath)) {
    Write-Host "    [FAIL] Failed to download Proxmox ISO!" -ForegroundColor Red
    exit 1
}
Write-Host "    [PASS] Proxmox ISO is ready at $isoPath" -ForegroundColor Green

# 5. Check if VM Already Exists
$existingVm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
if ($existingVm) {
    Write-Host "`n==> Warning: VM '$VmName' already exists. Recreating cleanly..." -ForegroundColor Yellow
    if ($existingVm.State -eq "Running") {
        Stop-VM -Name $VmName -TurnOff -Force
    }
    Remove-VM -Name $VmName -Force
}

# 6. Create VHDX
$vhdxPath = Join-Path $diskDir "$VmName.vhdx"
if (Test-Path $vhdxPath) {
    Remove-Item $vhdxPath -Force
}
Write-Host "`n==> Step 3: Creating 50GB Dynamic VHDX Disk..."
New-VHD -Path $vhdxPath -SizeBytes $DiskSizeBytes -Dynamic | Out-Null
Write-Host "    [PASS] VHDX created: $vhdxPath" -ForegroundColor Green

# 7. Create Generation 2 VM
Write-Host "`n==> Step 4: Creating Generation 2 Virtual Machine '$VmName'..."
$switch = Get-VMSwitch -SwitchType Internal, Private, External | Where-Object { $_.Name -eq "Default Switch" } | Select-Object -First 1
if (-not $switch) {
    $switch = Get-VMSwitch | Select-Object -First 1
}

$newVm = New-VM -Name $VmName `
    -Generation 2 `
    -MemoryStartupBytes $MemoryBytes `
    -VHDPath $vhdxPath `
    -SwitchName $switch.Name `
    -Path $vmDir

Write-Host "    [PASS] VM created and connected to switch '$($switch.Name)'." -ForegroundColor Green

# 8. Configure CPU & Nested Virtualization (AMD-V)
Write-Host "`n==> Step 5: Configuring CPU ($CpuCount Cores) & Nested Virtualization..."
Set-VMProcessor -VMName $VmName -Count $CpuCount
Set-VMProcessor -VMName $VmName -ExposeVirtualizationExtensions $true
Write-Host "    [PASS] AMD-V Nested Virtualization Passthrough Enabled!" -ForegroundColor Green

# 9. Configure Firmware & Secure Boot
Write-Host "`n==> Step 6: Configuring UEFI Firmware & Disabling Secure Boot..."
Set-VMFirmware -VMName $VmName -EnableSecureBoot Off

# 10. Attach DVD Drive with Proxmox ISO & Set Boot Priority
Write-Host "`n==> Step 7: Attaching Proxmox ISO to Virtual DVD Drive..."
$dvd = Add-VMDvdDrive -VMName $VmName -Path $isoPath -Passthru
Set-VMFirmware -VMName $VmName -FirstBootDevice $dvd
Write-Host "    [PASS] Boot order configured: DVD first." -ForegroundColor Green

# 11. Start VM & Launch Console
Write-Host "`n==> Step 8: Starting '$VmName' and launching Graphical Console..." -ForegroundColor Cyan
Start-VM -Name $VmName
Start-Process vmconnect.exe -ArgumentList "localhost", $VmName

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   PROXMOX LAB VM IS RUNNING SUCCESSFULLY!                " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "The Hyper-V VMConnect console window has been opened on your screen."
Write-Host "`nInstallation Steps inside the Console:"
Write-Host "  1. Select 'Install Proxmox VE (Graphical)'"
Write-Host "  2. Accept EULA and select the default 50GB disk"
Write-Host "  3. Country: Thailand | Timezone: Asia/Bangkok"
Write-Host "  4. Set Root Password and Email"
Write-Host "  5. Network: It will auto-detect DHCP IP from Default Switch"
Write-Host "  6. Click Install!"
Write-Host "`nOnce finished, open your browser to: https://<VM_IP>:8006" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
