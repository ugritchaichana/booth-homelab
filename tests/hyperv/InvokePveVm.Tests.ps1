BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'HyperVStubs.psm1') -Force
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\HomelabHyperV.psm1')).ProviderPath -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:savedLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $TestDrive
    $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\Invoke-PveVm.ps1')).ProviderPath
    $script:configPath = $script:FixturePath

    $st = @{}
    $script:st = $st

    Mock Import-Module {}
    Mock Write-Host {}
    Mock Write-HomelabLog {}
    Mock Start-Sleep { [Threading.Thread]::Sleep(20) }
    Mock Get-HomelabHyperVRight ({ $st.Rights }.GetNewClosure())
    Mock Get-VM ({ $i = [math]::Min($st.GetVmCalls, $st.Vms.Count - 1); $st.GetVmCalls++; $st.Vms[$i] }.GetNewClosure())
    Mock Get-VMSnapshot ({ if ($st.Created) { $st.AfterCalls++; if ($st.AfterCalls -gt $st.Lag) { $st.After } } else { $st.Existing } }.GetNewClosure())
    Mock Get-VMDvdDrive ({ param($VMName, $VMSnapshot) if ($VMSnapshot) { $st.SnapDvd } else { $st.Dvd } }.GetNewClosure())
    Mock Get-VMHardDiskDrive ({ param($VMName, $VMSnapshot) if ($VMSnapshot) { $st.SnapDisks } else { $st.Disks } }.GetNewClosure())
    Mock Get-VHD ({ param($Path) $st.Vhd[$Path] }.GetNewClosure())
    Mock Get-PSDrive ({ [pscustomobject]@{ Free = $st.Free } }.GetNewClosure())
    Mock Checkpoint-VM ({ $st.Created = $true; $st.CheckpointCalls++; [pscustomobject]@{ Id = $st.NewId } }.GetNewClosure())
    Mock Remove-VMSnapshot ({ $st.Removed++; if ($st.RemoveThrows) { throw 'remove refused' } }.GetNewClosure())
    Mock Stop-VM ({ param($Name, $TurnOff, $Force) if ($st.StopThrows) { throw 'stop refused' }; if (-not $st.StopStays) { $st.Vms[0].State = 'Off' } }.GetNewClosure())
    Mock Start-VM {}
    Mock Connect-VMNetworkAdapter {}
    Mock Get-HomelabAvailableMemory ({ $st.Memory }.GetNewClosure())
    Mock Get-PveFirewallState ({ $st.Firewall }.GetNewClosure())
    Mock Get-PveVmAdapter ({ $st.Nic }.GetNewClosure())
    Mock Sync-PveIsolation ({ if ($st.SyncThrows) { throw 'sync refused' }; $st.Sync }.GetNewClosure())
    Mock Wait-PveTcpPort ({ $st.BootSeconds }.GetNewClosure())
    Mock Get-PveDenyInput ({ $st.Deny }.GetNewClosure())
    Mock Get-PveAclPlan ({ $st.Plan }.GetNewClosure())
    Mock Get-PveOwnAcl ({ $st.Own }.GetNewClosure())
    Mock Get-PveForeignAcl ({ $st.Foreign }.GetNewClosure())
    Mock Test-PveTcpPort ({ $st.Tcp }.GetNewClosure())
    Mock Write-PveDenySummary {}
    Mock Get-NetAdapterBinding {}

    function script:Reset-State {
        $newId = [guid]::NewGuid()
        $vm = [pscustomobject]@{ Name = 'lab-vm'; State = 'Off'; Uptime = [timespan]::Zero; MemoryAssigned = 0 }
        $st.Rights = [pscustomobject]@{ Elevated = $true; InHyperVAdminsToken = $true; HasRights = $true; MemberConfigured = $true }
        $st.Vms = @($vm)
        $st.GetVmCalls = 0
        $st.Existing = @()
        $st.After = @([pscustomobject]@{ Id = $newId; Name = 'before-upgrade'; State = 'Off' })
        $st.NewId = $newId
        $st.Created = $false
        $st.AfterCalls = 0
        $st.Lag = 0
        $st.CheckpointCalls = 0
        $st.Removed = 0
        $st.RemoveThrows = $false
        $st.Dvd = @([pscustomobject]@{ Path = ''; DvdMediaType = 'None'; ControllerNumber = 0; ControllerLocation = 1 })
        $st.SnapDvd = @()
        $st.Disks = @([pscustomobject]@{ Path = 'D:\lab\lab-vm.vhdx' })
        $st.SnapDisks = @()
        $st.Vhd = @{ 'D:\lab\lab-vm.vhdx' = [pscustomobject]@{ FileSize = 10GB; ParentPath = $null } }
        $st.Free = 500GB
        $st.StopThrows = $false
        $st.StopStays = $false
        $st.Memory = 30GB
        $st.Firewall = 'present'
        $st.Nic = [pscustomobject]@{ SwitchName = 'lab-switch' }
        $st.Sync = [pscustomobject]@{ Result = [pscustomobject]@{ Added = 0; Removed = 0; Desired = @(1..16) } }
        $st.SyncThrows = $false
        $st.BootSeconds = 12.3
        $st.Deny = [pscustomobject]@{ EgressInterfaceAlias = @('Uplink A'); EgressSource = 'configured'; DenyAll = $false; Extra = @(); NewPrefix = @() }
        $st.Plan = @(1..16)
        $st.Own = @(1..16 | ForEach-Object { [pscustomobject]@{ Weight = 4000 + $_ } })
        $st.Foreign = @()
        $st.Tcp = $true
    }

    function script:Invoke-Pve {
        param([string]$Action, [hashtable]$More = @{}, [string]$Config = $script:configPath)
        $global:LASTEXITCODE = -1
        & $script:scriptPath -Action $Action -ConfigPath $Config @More | Out-Null
        $global:LASTEXITCODE
    }
}

AfterAll {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Module HomelabHyperV, HyperVStubs -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-PveVm.ps1 rights and VM lookup (Invoke-PveVm.ps1:249-271)' {
    BeforeEach { Reset-State }

    It 'exits 3 for <Action> without Hyper-V rights and touches no VM (Invoke-PveVm.ps1:253-257)' -TestCases @(
        @{ Action = 'Status' }, @{ Action = 'Start' }, @{ Action = 'Refresh' }, @{ Action = 'Stop' }, @{ Action = 'Checkpoint' }
    ) {
        $st.Rights = [pscustomobject]@{ Elevated = $false; InHyperVAdminsToken = $false; HasRights = $false; MemberConfigured = $false }
        Invoke-Pve $Action | Should -Be 3
        Should -Invoke Get-VM -Times 0 -Exactly
        Should -Invoke Start-VM -Times 0 -Exactly
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'tells a user who is configured but not yet signed in again to sign out (Invoke-PveVm.ps1:21-23)' {
        $st.Rights = [pscustomobject]@{ HasRights = $false; MemberConfigured = $true }
        Invoke-Pve 'Status' | Should -Be 3
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*Sign out and sign in again*' }
    }

    It 'tells a user who is not in the group to run the setup elevated (Invoke-PveVm.ps1:24)' {
        $st.Rights = [pscustomobject]@{ HasRights = $false; MemberConfigured = $false }
        Invoke-Pve 'Status' | Should -Be 3
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*not in Hyper-V Administrators*' }
    }

    It 'says every action needs elevation when the config declines the group membership (Invoke-PveVm.ps1:18-20)' {
        $st.Rights = [pscustomobject]@{ HasRights = $false; MemberConfigured = $false }
        $f = New-FixtureFile -Replace @{ 'AddOwnerToHyperVAdministrators\s+=\s+\$true' = 'AddOwnerToHyperVAdministrators = $false' }
        Invoke-Pve 'Status' -Config $f | Should -Be 3
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*every action needs an elevated prompt*' }
    }

    It 'exits 1 when the VM does not exist (Invoke-PveVm.ps1:259-262)' {
        $st.Vms = @($null)
        Invoke-Pve 'Status' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -like "*VM 'lab-vm' does not exist*" }
    }

    It 'exits 1 and reports the error when the config file is missing (Invoke-PveVm.ps1:276)' {
        Invoke-Pve 'Status' -Config (Join-Path $TestDrive 'nope.psd1') | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -like 'Config file not found*' }
    }

    It 'rejects an unknown action at parameter binding' {
        { & $scriptPath -Action 'Reboot' -ConfigPath $configPath } | Should -Throw
    }
}

Describe 'Checkpoint action (Invoke-PveVm.ps1:186-247)' {
    BeforeEach { Reset-State }

    It 'takes a checkpoint of a stopped VM and exits 0 (Invoke-PveVm.ps1:222-246)' {
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
        Should -Invoke Checkpoint-VM -Times 1 -Exactly -ParameterFilter { $Name -eq 'lab-vm' -and $SnapshotName -eq 'before-upgrade' }
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Pass' -and $Message -like 'checkpoint "before-upgrade" taken while Off' }
    }

    It 'refuses while the VM is <State> and takes nothing (Invoke-PveVm.ps1:192-195)' -TestCases @(
        @{ State = 'Running' }, @{ State = 'Paused' }, @{ State = 'Saved' }, @{ State = 'Starting' }
    ) {
        $st.Vms[0].State = $State
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -like "VM is $State; a checkpoint is taken only while the VM is Off*" }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
        Should -Invoke Get-VMSnapshot -Times 0 -Exactly
    }

    It 'refuses a duplicate checkpoint name and takes nothing (Invoke-PveVm.ps1:196-200)' {
        $st.Existing = @([pscustomobject]@{ Name = 'before-upgrade'; Id = [guid]::NewGuid() })
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'checkpoint "before-upgrade" already exists*' }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'allows a different name next to an existing checkpoint (Invoke-PveVm.ps1:197)' {
        $st.Existing = @([pscustomobject]@{ Name = 'older'; Id = [guid]::NewGuid() })
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
    }

    It 'refuses the name <Name> and takes nothing (Invoke-PveVm.ps1:188-191)' -TestCases @(
        @{ Name = '' }, @{ Name = 'Upper' }, @{ Name = '-lead' }, @{ Name = 'has space' }, @{ Name = 'under_score' }
        @{ Name = ('a' * 64) }, @{ Name = "trail`n" }
    ) {
        $more = @{}
        if ($Name) { $more.Name = $Name }
        Invoke-Pve 'Checkpoint' $more | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'checkpoint needs -Name*' }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'accepts the 63-character boundary name and a single character (Invoke-PveVm.ps1:188)' {
        Invoke-Pve 'Checkpoint' @{ Name = ('a' * 63) } | Should -Be 0
        $st.Created = $false
        Invoke-Pve 'Checkpoint' @{ Name = '9' } | Should -Be 0
    }

    It 'refuses while a DVD drive still holds media by path (Invoke-PveVm.ps1:201-205)' {
        $st.Dvd = @([pscustomobject]@{ Path = 'D:\lab\install.iso'; DvdMediaType = 'ISO'; ControllerNumber = 0; ControllerLocation = 1 })
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '1 DVD drive(s) still hold media (controller 0/1)*' }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'refuses while a DVD drive reports a media type without a path (Invoke-PveVm.ps1:168)' {
        $st.Dvd = @([pscustomobject]@{ Path = ''; DvdMediaType = 'ISO'; ControllerNumber = 0; ControllerLocation = 0 })
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
    }

    It 'does not count an empty drive or a VM with no DVD drive as loaded media (Invoke-PveVm.ps1:168,201)' {
        $st.Dvd = @()
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
    }

    It 'refuses when free space is already below the floor and reports the disk chain (Invoke-PveVm.ps1:208-216)' {
        $st.Free = 10GB
        $st.Disks = @([pscustomobject]@{ Path = 'D:\lab\lab-vm.avhdx' })
        $st.Vhd = @{
            'D:\lab\lab-vm.avhdx' = [pscustomobject]@{ FileSize = 2GB; ParentPath = 'D:\lab\lab-vm.vhdx' }
            'D:\lab\lab-vm.vhdx' = [pscustomobject]@{ FileSize = 10GB; ParentPath = $null }
        }
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -like 'not enough free disk for a checkpoint*disk chain 12[.,]0 GiB*' }
        Should -Invoke Get-PSDrive -ParameterFilter { $Name -eq 'D' }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'warns but proceeds when only the worst case is below the floor (Invoke-PveVm.ps1:217)' {
        $st.Free = 140GB
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'the worst case is below the floor*' }
    }

    It 'does not warn when there is room for the worst case (Invoke-PveVm.ps1:217)' {
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
        Should -Invoke Write-HomelabLog -Times 0 -ParameterFilter { $Level -eq 'Warn' }
    }

    It 'counts the checkpoint disks in the chain without double-counting shared parents (Invoke-PveVm.ps1:171-183)' {
        $st.Free = 10GB
        $st.Existing = @([pscustomobject]@{ Name = 'older'; Id = [guid]::NewGuid() })
        $st.Disks = @([pscustomobject]@{ Path = 'D:\lab\head.avhdx' })
        $st.SnapDisks = @([pscustomobject]@{ Path = 'D:\lab\mid.avhdx' })
        $st.Vhd = @{
            'D:\lab\head.avhdx' = [pscustomobject]@{ FileSize = 1GB; ParentPath = 'D:\lab\mid.avhdx' }
            'D:\lab\mid.avhdx' = [pscustomobject]@{ FileSize = 2GB; ParentPath = 'D:\lab\base.vhdx' }
            'D:\lab\base.vhdx' = [pscustomobject]@{ FileSize = 4GB; ParentPath = $null }
        }
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*1 checkpoint(s), disk chain 7[.,]0 GiB*' }
    }

    It 'refuses when the VM left Off between the checks and the call (Invoke-PveVm.ps1:218-221)' {
        $running = [pscustomobject]@{ Name = 'lab-vm'; State = 'Running' }
        $st.Vms = @($st.Vms[0], $running)
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'VM left Off before the checkpoint*' }
        Should -Invoke Checkpoint-VM -Times 0 -Exactly
    }

    It 'waits for a checkpoint that appears late in the list (Invoke-PveVm.ps1:224-228)' {
        $st.Lag = 3
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
        Should -Invoke Start-Sleep -Times 3 -Exactly
    }

    It 'fails when the checkpoint never shows up in the list (Invoke-PveVm.ps1:229-232)' {
        $st.Lag = 1000
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*is listed 0 times*' }
        Should -Invoke Remove-VMSnapshot -Times 0 -Exactly
    }

    It 'finds the checkpoint by name when the created object carries no id (Invoke-PveVm.ps1:225)' {
        $st.NewId = $null
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 0
    }

    It 'removes a checkpoint that recorded a running state and exits 1 (Invoke-PveVm.ps1:234-243)' {
        $st.After[0].State = 'Running'
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Remove-VMSnapshot -Times 1 -Exactly
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*recorded state Running and 0 DVD medium(s); removed it.' }
    }

    It 'removes a checkpoint that recorded DVD media and exits 1 (Invoke-PveVm.ps1:233-243)' {
        $st.SnapDvd = @([pscustomobject]@{ Path = 'D:\lab\install.iso'; DvdMediaType = 'ISO' })
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Remove-VMSnapshot -Times 1 -Exactly
    }

    It 'tells the operator to remove it by hand when the cleanup fails (Invoke-PveVm.ps1:238-240)' {
        $st.After[0].State = 'Running'
        $st.RemoveThrows = $true
        Invoke-Pve 'Checkpoint' @{ Name = 'before-upgrade' } | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*removing it failed (remove refused)*' }
    }
}

Describe 'Start action (Invoke-PveVm.ps1:75-120)' {
    BeforeEach { Reset-State }

    It 'starts an Off VM, waits for ssh and exits 0 (Invoke-PveVm.ps1:111-119)' {
        Invoke-Pve 'Start' | Should -Be 0
        Should -Invoke Sync-PveIsolation -Times 1 -Exactly
        Should -Invoke Start-VM -Times 1 -Exactly -ParameterFilter { $Name -eq 'lab-vm' }
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'TCP 10.99.0.2:22 answered 12*s after Start-VM' }
    }

    It 'syncs the ACLs before it starts the VM (Invoke-PveVm.ps1:101,112)' {
        $order = New-Object System.Collections.ArrayList
        $st = $script:st
        Mock Sync-PveIsolation ({ [void]$order.Add('sync'); $st.Sync }.GetNewClosure())
        Mock Start-VM ({ [void]$order.Add('start') }.GetNewClosure())
        Invoke-Pve 'Start' | Should -Be 0
        $order | Should -Be @('sync', 'start')
    }

    It 'refuses a VM in state <State> (Invoke-PveVm.ps1:78)' -TestCases @(@{ State = 'Paused' }, @{ State = 'Saved' }, @{ State = 'Starting' }) {
        $st.Vms[0].State = $State
        Invoke-Pve 'Start' | Should -Be 1
        Should -Invoke Start-VM -Times 0 -Exactly
    }

    It 'refuses on low host RAM without -Force (Invoke-PveVm.ps1:83-87)' {
        $st.Memory = 10GB
        Invoke-Pve 'Start' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'RAM preflight refused*' }
        Should -Invoke Start-VM -Times 0 -Exactly
        Should -Invoke Sync-PveIsolation -Times 0 -Exactly
    }

    It 'starts despite low host RAM with -Force and logs the override (Invoke-PveVm.ps1:88)' {
        $st.Memory = 10GB
        Invoke-Pve 'Start' @{ Force = $true } | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'RAM preflight overridden by -Force*' }
        Should -Invoke Start-VM -Times 1 -Exactly
    }

    It 'refuses when the host firewall rule is <State> without -Force (Invoke-PveVm.ps1:93-97)' -TestCases @(
        @{ State = 'absent' }, @{ State = 'misconfigured' }, @{ State = 'unreadable' }
    ) {
        $st.Firewall = $State
        Invoke-Pve 'Start' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like "host firewall rule is $State; the second isolation plane is missing*" }
        Should -Invoke Start-VM -Times 0 -Exactly
    }

    It 'continues past a missing firewall rule with -Force (Invoke-PveVm.ps1:99)' {
        $st.Firewall = 'absent'
        Invoke-Pve 'Start' @{ Force = $true } | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like '*continuing because of -Force' }
    }

    It 'reconnects a disconnected adapter only after the sync (Invoke-PveVm.ps1:102-106)' {
        $st.Nic = [pscustomobject]@{ SwitchName = '' }
        Invoke-Pve 'Start' | Should -Be 0
        Should -Invoke Connect-VMNetworkAdapter -Times 1 -Exactly -ParameterFilter { $SwitchName -eq 'lab-switch' }
    }

    It 'only refreshes and reconnects a VM that is already running (Invoke-PveVm.ps1:107-110)' {
        $st.Vms[0].State = 'Running'
        $st.Memory = 1GB
        Invoke-Pve 'Start' | Should -Be 0
        Should -Invoke Start-VM -Times 0 -Exactly
        Should -Invoke Sync-PveIsolation -Times 1 -Exactly
    }

    It 'exits 1 when ssh never answers within the boot timeout (Invoke-PveVm.ps1:114-117)' {
        $st.BootSeconds = $null
        Invoke-Pve 'Start' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -like 'TCP 10.99.0.2:22 did not answer within 10 min' }
    }

    It 'does not start the VM when the ACL sync fails (Invoke-PveVm.ps1:101,276)' {
        $st.SyncThrows = $true
        Invoke-Pve 'Start' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Fail' -and $Message -eq 'sync refused' }
        Should -Invoke Start-VM -Times 0 -Exactly
    }

    It 'reports the already-matching case and the refreshed case differently (Invoke-PveVm.ps1:68-72)' {
        Invoke-Pve 'Start' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'port ACLs already match the current routes (16 rules)' }
        $st.Sync = [pscustomobject]@{ Result = [pscustomobject]@{ Added = 2; Removed = 1; Desired = @((New-TestAcl -Weight 4000), (New-TestAcl -Weight 4001)) } }
        Invoke-Pve 'Start' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'port ACLs refreshed (added 2, removed 1)*' }
    }
}

Describe 'Refresh action (Invoke-PveVm.ps1:122-136)' {
    BeforeEach { Reset-State }

    It 'does nothing and exits 0 when the VM is <State> (Invoke-PveVm.ps1:124-127)' -TestCases @(@{ State = 'Off' }, @{ State = 'Saved' }) {
        $st.Vms[0].State = $State
        Invoke-Pve 'Refresh' | Should -Be 0
        Should -Invoke Sync-PveIsolation -Times 0 -Exactly
    }

    It 'syncs a running VM and never starts or reconnects it (Invoke-PveVm.ps1:128-135)' {
        $st.Vms[0].State = 'Running'
        Invoke-Pve 'Refresh' | Should -Be 0
        Should -Invoke Sync-PveIsolation -Times 1 -Exactly
        Should -Invoke Start-VM -Times 0 -Exactly
        Should -Invoke Connect-VMNetworkAdapter -Times 0 -Exactly
    }

    It 'warns about a missing firewall rule but still syncs (Invoke-PveVm.ps1:129)' {
        $st.Vms[0].State = 'Running'
        $st.Firewall = 'absent'
        Invoke-Pve 'Refresh' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'host firewall rule is absent; Refresh cannot repair it*' }
    }

    It 'warns about a disconnected adapter and does not reconnect it (Invoke-PveVm.ps1:132-134)' {
        $st.Vms[0].State = 'Running'
        $st.Nic = [pscustomobject]@{ SwitchName = '' }
        Invoke-Pve 'Refresh' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'the network adapter is disconnected*' }
        Should -Invoke Connect-VMNetworkAdapter -Times 0 -Exactly
    }

    It 'exits 1 when the sync fails (Invoke-PveVm.ps1:130,276)' {
        $st.Vms[0].State = 'Running'
        $st.SyncThrows = $true
        Invoke-Pve 'Refresh' | Should -Be 1
    }
}

Describe 'Stop action (Invoke-PveVm.ps1:138-164)' {
    BeforeEach { Reset-State }

    It 'succeeds without a call when the VM is already Off (Invoke-PveVm.ps1:140)' {
        Invoke-Pve 'Stop' | Should -Be 0
        Should -Invoke Stop-VM -Times 0 -Exactly
    }

    It 'requests a graceful shutdown and exits 0 once the VM is Off (Invoke-PveVm.ps1:147-157)' {
        $st.Vms[0].State = 'Running'
        Invoke-Pve 'Stop' | Should -Be 0
        Should -Invoke Stop-VM -Times 1 -Exactly -ParameterFilter { -not $TurnOff }
    }

    It 'refuses a hard power-off without -Force (Invoke-PveVm.ps1:142)' {
        $st.Vms[0].State = 'Running'
        Invoke-Pve 'Stop' @{ TurnOff = $true } | Should -Be 1
        Should -Invoke Stop-VM -Times 0 -Exactly
    }

    It 'powers off hard with -TurnOff -Force (Invoke-PveVm.ps1:143-145)' {
        $st.Vms[0].State = 'Running'
        Invoke-Pve 'Stop' @{ TurnOff = $true; Force = $true } | Should -Be 0
        Should -Invoke Stop-VM -Times 1 -Exactly -ParameterFilter { $TurnOff -and $Force }
    }

    It 'exits 1 when the graceful request is rejected (Invoke-PveVm.ps1:149-152)' {
        $st.Vms[0].State = 'Running'
        $st.StopThrows = $true
        Invoke-Pve 'Stop' | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'graceful shutdown request failed: stop refused*' }
    }

    It 'exits 1 when the VM is still not Off after the timeout (Invoke-PveVm.ps1:154-163)' {
        $f = New-FixtureFile -Replace @{ 'StopTimeoutSeconds\s+=\s+180' = 'StopTimeoutSeconds = 1' }
        $st.Vms[0].State = 'Running'
        $st.StopStays = $true
        Invoke-Pve 'Stop' -Config $f | Should -Be 1
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'VM still not Off after 1 s*' }
    }
}

Describe 'Status action (Invoke-PveVm.ps1:27-62)' {
    BeforeEach { Reset-State }

    It 'probes ssh and web only for a running VM and exits 0 (Invoke-PveVm.ps1:37-40)' {
        $st.Vms[0].State = 'Running'
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Test-PveTcpPort -Times 1 -Exactly -ParameterFilter { $Port -eq 22 -and $Address -eq '10.99.0.2' }
        Should -Invoke Test-PveTcpPort -Times 1 -Exactly -ParameterFilter { $Port -eq 8006 }
    }

    It 'does not probe the guest when the VM is Off (Invoke-PveVm.ps1:37)' {
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Test-PveTcpPort -Times 0 -Exactly
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'TCP 10.99.0.2:22 reachable: False' }
    }

    It 'warns about foreign ACLs and a disconnected adapter (Invoke-PveVm.ps1:46,51-53)' {
        $st.Foreign = @([pscustomobject]@{ Weight = 100; Direction = 'Inbound'; Action = 'Allow' })
        $st.Nic = [pscustomobject]@{ SwitchName = '' }
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*outside the reserved weight range: 1 (100 Inbound Allow)*' }
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*NOT connected to the homelab switch*' }
    }

    It 'warns when the rule count differs from a fresh refresh and when the firewall rule is not present (Invoke-PveVm.ps1:49,57)' {
        $st.Own = @($st.Own | Select-Object -First 5)
        $st.Firewall = 'absent'
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like '*adapter: 5 (a fresh refresh would hold 16;*' }
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Warn' -and $Message -like 'host firewall rule lab-block-guest-inbound: absent' }
    }

    It 'reports a clean state with pass levels (Invoke-PveVm.ps1:44,48,56)' {
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Write-HomelabLog -Times 0 -ParameterFilter { $Level -eq 'Warn' }
        Should -Invoke Write-HomelabLog -ParameterFilter { $Level -eq 'Pass' -and $Message -like "network adapter: connected to 'lab-switch'" }
    }

    It 'prints the IPv6 binding of the host adapter when it is readable (Invoke-PveVm.ps1:59-60)' {
        Mock Get-NetAdapterBinding { [pscustomobject]@{ Enabled = $false } }
        Invoke-Pve 'Status' | Should -Be 0
        Should -Invoke Write-HomelabLog -ParameterFilter { $Message -like 'host vEthernet IPv6 binding enabled: False' }
    }
}
