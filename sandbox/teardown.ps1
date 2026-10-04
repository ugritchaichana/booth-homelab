<#
.SYNOPSIS
    One-command zero-trace teardown for SDET MinIO Sandbox.
#>
$ErrorActionPreference = "Stop"

$composeFile = Join-Path $PSScriptRoot "docker-compose.sandbox.yml"
Write-Host "==> [Teardown] Tearing down SDET Sandbox and removing volumes..." -ForegroundColor Yellow
docker compose -f $composeFile down -v --remove-orphans
Write-Host "==> [Teardown] Done. Local environment is clean." -ForegroundColor Green
