<#
.SYNOPSIS
    Reports, and with -Apply sets, the Hyper-V auto-start policy of the Proxmox VM.
.DESCRIPTION
    Run in an elevated PowerShell on the Windows homelab PC.
    Without -Apply the script only reports the VM state and its start/stop actions.
    With -Apply it sets AutomaticStartAction Start, AutomaticStartDelay 30 and the chosen stop action.
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$VmName = "Proxmox-Lab",
    [switch]$Apply,
    [ValidateSet("Save", "ShutDown", "TurnOff")]
    [string]$StopAction = "Save"
)

$ErrorActionPreference = "Stop"

function Show-VmPolicy {
    param([string]$Label)
    $vm = Get-VM -Name $VmName
    Write-Host ("{0}: Name={1} State={2} AutomaticStartAction={3} AutomaticStartDelay={4}s AutomaticStopAction={5}" -f `
            $Label, $vm.Name, $vm.State, $vm.AutomaticStartAction, $vm.AutomaticStartDelay, $vm.AutomaticStopAction)
    return $vm
}

$vm = Show-VmPolicy -Label "Current"

$nested = (Get-VMProcessor -VMName $VmName).ExposeVirtualizationExtensions
if ($nested -and $StopAction -eq "Save") {
    Write-Host "WARNING: nested virtualization is enabled on this VM; Hyper-V may not support Save state for it. Use -StopAction ShutDown if the VM comes back cold." -ForegroundColor Yellow
}

if (-not $Apply) {
    Write-Host "Report only. Re-run with -Apply to set AutomaticStartAction Start, AutomaticStartDelay 30, AutomaticStopAction $StopAction."
    exit 0
}

Set-VM -Name $VmName -AutomaticStartAction Start -AutomaticStartDelay 30 -AutomaticStopAction $StopAction
$vm = Show-VmPolicy -Label "Applied"

if ($vm.AutomaticStartAction -ne "Start") {
    Write-Host "AutomaticStartAction is not Start after Set-VM." -ForegroundColor Red
    exit 1
}
