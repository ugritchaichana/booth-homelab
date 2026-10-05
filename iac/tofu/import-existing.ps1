<#
.SYNOPSIS
    Imports existing live Proxmox LXC containers (CT 102, 103, 104) into OpenTofu state.
.DESCRIPTION
    Binds running infrastructure to OpenTofu code, eliminating unmanaged state
    and aligning with enterprise IaC governance standards.
.PARAMETER NodeName
    The target Proxmox VE node name (default: "pve").
#>
[CmdletBinding()]
param(
    [string]$NodeName = "pve",
    [string]$TofuBin = "tofu"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Resolve tofu binary
if (-not (Get-Command $TofuBin -ErrorAction SilentlyContinue)) {
    $wingetTofu = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\OpenTofu.Tofu_Microsoft.Winget.Source_8wekyb3d8bbwe\tofu.exe"
    if (Test-Path $wingetTofu) {
        $TofuBin = $wingetTofu
    } else {
        Write-Error "OpenTofu binary not found. Please ensure 'tofu' is in PATH or installed via winget."
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "      OPENTOFU HOMELAB STATE IMPORT TOOLING               " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Target Proxmox Node: $NodeName"
Write-Host "IaC Working Dir:     $scriptDir"
Write-Host "OpenTofu Binary:     $TofuBin"
Write-Host ""

$targets = @(
    @{ Address = "module.runner_dotnet.proxmox_virtual_environment_container.this"; VmId = 102; Name = "gha-runner-01 (.NET)" },
    @{ Address = "module.runner_angular.proxmox_virtual_environment_container.this"; VmId = 103; Name = "gha-runner-angular (Angular)" },
    @{ Address = "module.minio_cache.proxmox_virtual_environment_container.this"; VmId = 104; Name = "minio-s3 (Remote Cache)" }
)

foreach ($target in $targets) {
    $importId = "$NodeName/$($target.VmId)"
    Write-Host "==> Importing $($target.Name) (CT $($target.VmId)) as $($target.Address)..." -ForegroundColor Yellow
    try {
        & $TofuBin -chdir=$scriptDir import $target.Address $importId
        Write-Host " [PASS] Successfully imported $($target.Name)." -ForegroundColor Green
    } catch {
        Write-Warning "Failed or already imported: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "==> Verifying OpenTofu State Drift..." -ForegroundColor Cyan
& $TofuBin -chdir=$scriptDir plan
