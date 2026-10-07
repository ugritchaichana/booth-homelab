[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Start', 'Stop', 'Status', 'Refresh', 'Checkpoint')][string]$Action,
    [string]$ConfigPath,
    [string]$Name,
    [switch]$Force,
    [switch]$TurnOff,
    [switch]$ShowPrefixes
)

$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'pve01.psd1' }
Import-Module (Join-Path $PSScriptRoot 'HomelabHyperV.psm1') -Force
$script:ShowPrefixes = $ShowPrefixes.IsPresent

function Get-RightsMessage {
    param($Rights, $Cfg)
    if (-not $Cfg.AddOwnerToHyperVAdministrators) {
        return 'AddOwnerToHyperVAdministrators is false in this configuration, so every action needs an elevated prompt.'
    }
    if ($Rights.MemberConfigured) {
        return 'You are in Hyper-V Administrators, but this session started before that took effect. Sign out and sign in again (or restart), then retry.'
    }
    'This account is not in Hyper-V Administrators. Run New-PveHost.ps1 once from an elevated prompt (it adds the current user), then sign out and in.'
}

function Write-VmStatus {
    param($Cfg, $Vm)
    $in = Get-PveDenyInput -Config $Cfg
    $expected = @(Get-PveAclPlan -Config $Cfg -ExtraDenyPrefix $in.Extra -DenyAllEgress:$in.DenyAll).Count
    $own = @(Get-PveOwnAcl -Config $Cfg)
    $slots = @($own | ForEach-Object { $_.Weight } | Select-Object -Unique).Count
    $foreign = @(Get-PveForeignAcl -Config $Cfg)
    $nic = Get-PveVmAdapter -Config $Cfg
    $ssh = $false
    $web = $false
    if ($Vm.State -eq 'Running') {
        $ssh = Test-PveTcpPort -Address $Cfg.GuestAddress -Port $Cfg.SshPort
        $web = Test-PveTcpPort -Address $Cfg.GuestAddress -Port $Cfg.WebPort
    }
    Write-HomelabLog -Level Info -Message ('VM {0}: state {1}, uptime {2}, assigned memory {3}' -f $Vm.Name, $Vm.State, $Vm.Uptime, (Format-HomelabGiB -Bytes $Vm.MemoryAssigned))
    Write-HomelabLog -Level Info -Message ('TCP {0}:{1} reachable: {2}' -f $Cfg.GuestAddress, $Cfg.SshPort, $ssh)
    Write-HomelabLog -Level Info -Message ('TCP {0}:{1} reachable: {2}' -f $Cfg.GuestAddress, $Cfg.WebPort, $web)
    $nicLevel = 'Pass'
    $nicText = "connected to '{0}'" -f $nic.SwitchName
    if ($nic.SwitchName -ne $Cfg.SwitchName) { $nicLevel = 'Warn'; $nicText = 'NOT connected to the homelab switch (Start reconnects it after a clean ACL sync)' }
    Write-HomelabLog -Level $nicLevel -Message ('network adapter: ' + $nicText)
    $aclLevel = 'Pass'
    if ($slots -ne $expected) { $aclLevel = 'Warn' }
    Write-HomelabLog -Level $aclLevel -Message ('port ACL rules of this script on the adapter: {0} (a fresh refresh would hold {1}; Start or Refresh brings them up to date)' -f $slots, $expected)
    if ($foreign.Count -gt 0) {
        Write-HomelabLog -Level Warn -Message ('extended ACLs outside the reserved weight range: {0} ({1}); Start will refuse until they are removed' -f $foreign.Count, (($foreign | ForEach-Object { '{0} {1} {2}' -f $_.Weight, $_.Direction, $_.Action }) -join '; '))
    }
    Write-PveDenySummary -DenyInput $in -ShowPrefixes:$script:ShowPrefixes
    $fwState = Get-PveFirewallState -Config $Cfg
    $fwLevel = 'Pass'
    if ($fwState -ne 'present') { $fwLevel = 'Warn' }
    Write-HomelabLog -Level $fwLevel -Message ('host firewall rule {0}: {1}' -f $Cfg.FirewallRuleName, $fwState)
    $v6 = Get-NetAdapterBinding -Name $Cfg.SwitchAdapterAlias -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if ($v6) { Write-HomelabLog -Level Info -Message ('host vEthernet IPv6 binding enabled: {0}' -f $v6.Enabled) }
    Write-HomelabLog -Level Info -Message ('checkpoints: {0}' -f @(Get-VMSnapshot -VMName $Cfg.VmName -ErrorAction SilentlyContinue).Count)
}

function Invoke-IsolationRefresh {
    param($Cfg)
    $r = Sync-PveIsolation -Config $Cfg -Persist -ShowPrefixes:$script:ShowPrefixes
    $res = $r.Result
    if ($res.Added -eq 0 -and $res.Removed -eq 0) {
        Write-HomelabLog -Level Pass -Message ('port ACLs already match the current routes ({0} rules)' -f @($res.Desired).Count)
    } else {
        Write-HomelabLog -Level Pass -Message ("port ACLs refreshed (added {0}, removed {1}):`n{2}" -f $res.Added, $res.Removed, (Format-PveAclTable -Rule $res.Desired -Config $Cfg -ShowPrefixes:$script:ShowPrefixes))
    }
}

function Invoke-StartAction {
    param($Cfg, $Vm, [bool]$Override)
    $running = ($Vm.State -eq 'Running')
    if (-not $running -and $Vm.State -ne 'Off') { throw ('VM is {0}; start needs it Off.' -f $Vm.State) }
    if (-not $running) {
        $avail = Get-HomelabAvailableMemory
        $remain = $avail - $Cfg.MemoryBytes
        $text = 'available {0}; after the VM {1}; need {2} GiB left' -f (Format-HomelabGiB -Bytes $avail), (Format-HomelabGiB -Bytes $remain), $Cfg.MinHostFreeRamAfterVmGiB
        if ($remain -lt ([int64]$Cfg.MinHostFreeRamAfterVmGiB * 1GB)) {
            if (-not $Override) {
                Write-HomelabLog -Level Fail -Message ('RAM preflight refused: ' + $text + '. Close other applications or use -Force.')
                return 1
            }
            Write-HomelabLog -Level Warn -Message ('RAM preflight overridden by -Force: ' + $text)
        } else {
            Write-HomelabLog -Level Pass -Message ('RAM: ' + $text)
        }
    }
    $fw = Get-PveFirewallState -Config $Cfg
    if ($fw -ne 'present') {
        if (-not $Override) {
            Write-HomelabLog -Level Fail -Message ('host firewall rule is {0}; the second isolation plane is missing. Re-run New-PveHost.ps1 elevated, or use -Force to start anyway.' -f $fw)
            return 1
        }
        Write-HomelabLog -Level Warn -Message ('host firewall rule is {0}; continuing because of -Force' -f $fw)
    }
    Invoke-IsolationRefresh -Cfg $Cfg
    $nic = Get-PveVmAdapter -Config $Cfg
    if ($nic.SwitchName -ne $Cfg.SwitchName) {
        Connect-VMNetworkAdapter -VMNetworkAdapter $nic -SwitchName $Cfg.SwitchName
        Write-HomelabLog -Level Pass -Message ("network adapter connected to '{0}' after a clean ACL sync" -f $Cfg.SwitchName)
    }
    if ($running) {
        Write-HomelabLog -Level Info -Message 'VM was already running; only the ACL refresh was applied.'
        return 0
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Start-VM -Name $Cfg.VmName
    $secs = Wait-PveTcpPort -Address $Cfg.GuestAddress -Port $Cfg.SshPort -TimeoutSeconds ($Cfg.BootTimeoutMinutes * 60) -Clock $clock -ProgressSeconds $Cfg.ProgressSeconds
    if ($null -eq $secs) {
        Write-HomelabLog -Level Fail -Message ('TCP {0}:{1} did not answer within {2} min' -f $Cfg.GuestAddress, $Cfg.SshPort, $Cfg.BootTimeoutMinutes)
        return 1
    }
    Write-HomelabLog -Level Pass -Message ('TCP {0}:{1} answered {2} s after Start-VM' -f $Cfg.GuestAddress, $Cfg.SshPort, $secs)
    0
}

function Invoke-RefreshAction {
    param($Cfg, $Vm)
    if ($Vm.State -ne 'Running') {
        Write-HomelabLog -Level Info -Message ('VM is {0}; nothing to refresh. Refresh never starts the VM.' -f $Vm.State)
        return 0
    }
    $fw = Get-PveFirewallState -Config $Cfg
    if ($fw -ne 'present') { Write-HomelabLog -Level Warn -Message ('host firewall rule is {0}; Refresh cannot repair it without elevation. Re-run New-PveHost.ps1 elevated.' -f $fw) }
    Invoke-IsolationRefresh -Cfg $Cfg
    $nic = Get-PveVmAdapter -Config $Cfg
    if ($nic.SwitchName -ne $Cfg.SwitchName) {
        Write-HomelabLog -Level Warn -Message 'the network adapter is disconnected (an earlier sync failed?). Refresh never reconnects; run -Action Start after checking Status.'
    }
    0
}

function Invoke-StopAction {
    param($Cfg, $Vm, [bool]$HardOff, [bool]$Confirmed)
    if ($Vm.State -eq 'Off') { Write-HomelabLog -Level Pass -Message 'VM is already Off'; return 0 }
    if ($HardOff) {
        if (-not $Confirmed) { Write-HomelabLog -Level Fail -Message '-TurnOff cuts power and can corrupt the guest disk; add -Force to confirm.'; return 1 }
        Stop-VM -Name $Cfg.VmName -TurnOff -Force
        Write-HomelabLog -Level Pass -Message 'VM powered off (hard)'
        return 0
    }
    try {
        Stop-VM -Name $Cfg.VmName -Confirm:$false
    } catch {
        Write-HomelabLog -Level Fail -Message ('graceful shutdown request failed: {0}. Shut the guest down from inside it, or use -TurnOff -Force.' -f $_.Exception.Message)
        return 1
    }
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $Cfg.StopTimeoutSeconds) {
        if ((Get-VM -Name $Cfg.VmName).State -eq 'Off') {
            Write-HomelabLog -Level Pass -Message ('VM is Off after {0} s' -f [int]$clock.Elapsed.TotalSeconds)
            return 0
        }
        Write-HomelabLog -Level Info -Message ('waiting for shutdown ... {0} s' -f [int]$clock.Elapsed.TotalSeconds)
        Start-Sleep -Seconds ([math]::Min($Cfg.ProgressSeconds, 10))
    }
    Write-HomelabLog -Level Fail -Message ('VM still not Off after {0} s. Use -TurnOff -Force if you accept a hard power-off.' -f $Cfg.StopTimeoutSeconds)
    1
}

function Test-DvdLoaded {
    param($Drive)
    [bool]($Drive.Path -or ($null -ne $Drive.DvdMediaType -and [string]$Drive.DvdMediaType -ne 'None'))
}

function Get-DiskChainSize {
    param([string]$VmName, $Snapshot)
    $seen = @{}
    $heads = @(@(Get-VMHardDiskDrive -VMName $VmName).Path)
    foreach ($snap in $Snapshot) { $heads += @(Get-VMHardDiskDrive -VMSnapshot $snap).Path }
    foreach ($path in $heads) {
        for ($depth = 0; $path -and $depth -lt 64 -and -not $seen.ContainsKey($path); $depth++) {
            $vhd = Get-VHD -Path $path
            $seen[$path] = [int64]$vhd.FileSize
            $path = $vhd.ParentPath
        }
    }
    [int64]($seen.Values | Measure-Object -Sum).Sum
}

function Invoke-CheckpointAction {
    param($Cfg, $Vm, [string]$SnapshotName)
    if (-not $SnapshotName -or $SnapshotName -cnotmatch '\A[a-z0-9][a-z0-9-]{0,62}\z') {
        Write-HomelabLog -Level Fail -Message 'checkpoint needs -Name: 1 to 63 characters, lowercase letters, digits and hyphens, starting with a letter or digit.'
        return 1
    }
    if ($Vm.State -ne 'Off') {
        Write-HomelabLog -Level Fail -Message ('VM is {0}; a checkpoint is taken only while the VM is Off (a running VM keeps memory state in the checkpoint). Run -Action Stop first.' -f $Vm.State)
        return 1
    }
    $existing = @(Get-VMSnapshot -VMName $Cfg.VmName)
    if (@($existing | Where-Object { $_.Name -eq $SnapshotName }).Count -gt 0) {
        Write-HomelabLog -Level Fail -Message ('checkpoint "{0}" already exists; pick another name.' -f $SnapshotName)
        return 1
    }
    $media = @(Get-VMDvdDrive -VMName $Cfg.VmName | Where-Object { Test-DvdLoaded -Drive $_ })
    if ($media.Count -gt 0) {
        Write-HomelabLog -Level Fail -Message ('{0} DVD drive(s) still hold media (controller {1}); eject before taking a checkpoint.' -f $media.Count, (($media | ForEach-Object { '{0}/{1}' -f $_.ControllerNumber, $_.ControllerLocation }) -join ', '))
        return 1
    }
    $diskPath = @(Get-VMHardDiskDrive -VMName $Cfg.VmName)[0].Path
    $driveRoot = [IO.Path]::GetPathRoot($diskPath)
    $free = [int64](Get-PSDrive -Name $driveRoot.Substring(0, 1)).Free
    $worst = $free - [int64]$Cfg.DiskBytes
    $floor = [int64]$Cfg.MinFreeDiskAfterGrowthGiB * 1GB
    $chain = Format-HomelabGiB -Bytes (Get-DiskChainSize -VmName $Cfg.VmName -Snapshot $existing)
    $diskText = '{0} free {1}; worst case after the new layer grows to {2} GiB: {3}; floor {4} GiB; {5} checkpoint(s), disk chain {6}' -f $driveRoot, (Format-HomelabGiB -Bytes $free), $Cfg.DiskGiB, (Format-HomelabGiB -Bytes $worst), $Cfg.MinFreeDiskAfterGrowthGiB, $existing.Count, $chain
    if ($free -lt $floor) {
        Write-HomelabLog -Level Fail -Message ('not enough free disk for a checkpoint: ' + $diskText + '. Remove a checkpoint with Remove-VMSnapshot once the step it protects is verified.')
        return 1
    }
    if ($worst -lt $floor) { Write-HomelabLog -Level Warn -Message ('the worst case is below the floor: ' + $diskText) }
    if ((Get-VM -Name $Cfg.VmName).State -ne 'Off') {
        Write-HomelabLog -Level Fail -Message 'VM left Off before the checkpoint; nothing taken.'
        return 1
    }
    $created = Checkpoint-VM -Name $Cfg.VmName -SnapshotName $SnapshotName -Passthru
    $snap = @()
    for ($try = 0; ; $try++) {
        $snap = @(Get-VMSnapshot -VMName $Cfg.VmName | Where-Object { if ($created.Id) { $_.Id -eq $created.Id } else { $_.Name -eq $SnapshotName } })
        if ($snap.Count -gt 0 -or $try -ge 30) { break }
        Start-Sleep -Milliseconds 500
    }
    if ($snap.Count -ne 1) {
        Write-HomelabLog -Level Fail -Message ('checkpoint "{0}" is listed {1} times 15 s after Checkpoint-VM returned; check Get-VMSnapshot before retrying.' -f $SnapshotName, $snap.Count)
        return 1
    }
    $recorded = @(Get-VMDvdDrive -VMSnapshot $snap[0] | Where-Object { Test-DvdLoaded -Drive $_ })
    if ($snap[0].State -ne 'Off' -or $recorded.Count -gt 0) {
        $badText = 'checkpoint "{0}" recorded state {1} and {2} DVD medium(s)' -f $SnapshotName, $snap[0].State, $recorded.Count
        try {
            Remove-VMSnapshot -VMSnapshot $snap[0]
        } catch {
            Write-HomelabLog -Level Fail -Message ('{0}; removing it failed ({1}). Remove it by hand with Remove-VMSnapshot.' -f $badText, $_.Exception.Message)
            return 1
        }
        Write-HomelabLog -Level Fail -Message ($badText + '; removed it.')
        return 1
    }
    Write-HomelabLog -Level Pass -Message ('checkpoint "{0}" taken while Off' -f $SnapshotName)
    0
}

function Invoke-Main {
    param([string]$Do, [bool]$Override, [bool]$HardOff, [string]$SnapshotName)
    $cfg = Import-PveConfig -Path $ConfigPath
    $rights = Get-HomelabHyperVRight
    if (-not $rights.HasRights) {
        Write-HomelabLog -Level Fail -Message 'Hyper-V rights are missing in this session, so the VM cannot be read or controlled.'
        Write-HomelabLog -Level Info -Message (Get-RightsMessage -Rights $rights -Cfg $cfg)
        return 3
    }
    $vm = Get-VM -Name $cfg.VmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-HomelabLog -Level Fail -Message ("VM '{0}' does not exist. Run New-PveHost.ps1 from an elevated prompt first." -f $cfg.VmName)
        return 1
    }
    switch ($Do) {
        'Status' { Write-VmStatus -Cfg $cfg -Vm $vm; return 0 }
        'Start' { return (Invoke-StartAction -Cfg $cfg -Vm $vm -Override $Override) }
        'Refresh' { return (Invoke-RefreshAction -Cfg $cfg -Vm $vm) }
        'Stop' { return (Invoke-StopAction -Cfg $cfg -Vm $vm -HardOff $HardOff -Confirmed $Override) }
        'Checkpoint' { return (Invoke-CheckpointAction -Cfg $cfg -Vm $vm -SnapshotName $SnapshotName) }
    }
}

$exitCode = 1
try {
    $exitCode = @(Invoke-Main -Do $Action -Override $Force.IsPresent -HardOff $TurnOff.IsPresent -SnapshotName $Name)[-1]
} catch {
    Write-HomelabLog -Level Fail -Message $_.Exception.Message
}
exit $exitCode
