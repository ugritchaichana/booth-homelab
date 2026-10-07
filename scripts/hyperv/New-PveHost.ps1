[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ConfigPath,
    [string]$InstallIso,
    [string]$InstallIsoSha256,
    [switch]$Install,
    [switch]$PlanOnly,
    [switch]$Uninstall,
    [switch]$ShowPrefixes
)

$ErrorActionPreference = 'Stop'
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'pve01.psd1' }
Import-Module (Join-Path $PSScriptRoot 'HomelabHyperV.psm1') -Force

$script:PlanMode = $PlanOnly.IsPresent -or $WhatIfPreference
$script:WantInstall = $Install.IsPresent
$script:IsoSource = $InstallIso
$script:IsoSha256 = $InstallIsoSha256
$script:UninstallRequested = $Uninstall.IsPresent
$script:ShowPrefixes = $ShowPrefixes.IsPresent
$script:IsoCopied = $false
$script:Cfg = $null
$script:Rights = $null
$script:IsoDest = $null
$script:MissingFeatures = @()
$script:Failures = 0
$script:NeedsRightsText = 'needs elevation/Hyper-V rights - skipped in plan'

function Write-PreflightResult {
    param([string]$Name, [ValidateSet('Pass', 'Warn', 'Fail', 'Skip')][string]$Status, [string]$Detail)
    if ($Status -eq 'Fail') { $script:Failures++ }
    Write-HomelabLog -Level $Status -Message ('{0}: {1}' -f $Name, $Detail)
}

function Invoke-Preflight {
    $cfg = $script:Cfg
    Write-HomelabLog -Level Step -Message 'Preflight'

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    $isClient = ([int]$os.ProductType -eq 1)
    $minBuild = 20348
    if ($isClient) { $minBuild = 22000 }
    if ($build -ge $minBuild) {
        Write-PreflightResult 'OS' 'Pass' ('{0} build {1}' -f $os.Caption, $build)
    } else {
        Write-PreflightResult 'OS' 'Fail' ("{0} build {1}; need Windows 11 (22000+) or Server 2022 (20348+)" -f $os.Caption, $build)
    }

    $script:MissingFeatures = @()
    if ($isClient) {
        $need = @('Microsoft-Hyper-V-Hypervisor', 'Microsoft-Hyper-V-Services', 'Microsoft-Hyper-V-Management-PowerShell')
        $feat = @(Get-CimInstance -ClassName Win32_OptionalFeature | Where-Object { $need -contains $_.Name })
        $script:MissingFeatures = @($need | Where-Object { $n = $_; @($feat | Where-Object { $_.Name -eq $n -and $_.InstallState -eq 1 }).Count -eq 0 })
    } elseif (-not (Get-Service -Name vmms -ErrorAction SilentlyContinue)) {
        $script:MissingFeatures = @('Hyper-V')
    }
    if ($script:MissingFeatures.Count -eq 0) {
        Write-PreflightResult 'Hyper-V features' 'Pass' 'enabled'
        $vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
        if ($vmms -and $vmms.Status -eq 'Running') {
            Write-PreflightResult 'vmms service' 'Pass' 'Running'
        } else {
            Write-PreflightResult 'vmms service' 'Fail' 'not running'
        }
    } else {
        Write-PreflightResult 'Hyper-V features' 'Warn' ('missing: {0}; would be enabled with -NoRestart and then stop with exit code 2' -f ($script:MissingFeatures -join ', '))
    }

    if ($script:Rights.HasRights -and $script:MissingFeatures.Count -eq 0) {
        try {
            $max = (Get-VMHostSupportedVersion | ForEach-Object { [version][string]$_.Version } | Sort-Object -Descending | Select-Object -First 1)
            if ($max -ge [version]$cfg.MinHostVmConfigVersion) {
                Write-PreflightResult 'VM config version' 'Pass' ('host supports up to {0}; nested virtualization needs {1}+' -f $max, $cfg.MinHostVmConfigVersion)
            } else {
                Write-PreflightResult 'VM config version' 'Fail' ('host supports up to {0}; need {1}+' -f $max, $cfg.MinHostVmConfigVersion)
            }
        } catch {
            Write-PreflightResult 'VM config version' 'Warn' ('unreadable: ' + $_.Exception.Message)
        }
    } else {
        Write-PreflightResult 'VM config version' 'Skip' $script:NeedsRightsText
    }

    $natRange = ConvertTo-IPv4Range -Cidr $cfg.NatPrefix
    $foreign = @()
    $ownNatPrefixOk = $true
    try {
        $nats = @(Get-NetNat -ErrorAction Stop)
        $foreign = @($nats | Where-Object { $_.Name -ne $cfg.NatName })
        $ours = @($nats | Where-Object { $_.Name -eq $cfg.NatName })
        if ($ours.Count -gt 0 -and $ours[0].InternalIPInterfaceAddressPrefix -ne $cfg.NatCidr) { $ownNatPrefixOk = $false }
        if ($foreign.Count -gt 0) {
            Write-PreflightResult 'NAT' 'Fail' ('a foreign NAT exists ({0}); WinNAT allows one NAT per host' -f (($foreign | ForEach-Object { $_.Name + ' ' + $_.InternalIPInterfaceAddressPrefix }) -join ', '))
        } elseif (-not $ownNatPrefixOk) {
            Write-PreflightResult 'NAT' 'Fail' ("NAT '{0}' exists with prefix {1}, config wants {2}" -f $cfg.NatName, $ours[0].InternalIPInterfaceAddressPrefix, $cfg.NatCidr)
        } else {
            Write-PreflightResult 'NAT' 'Pass' 'no foreign NAT'
        }
    } catch {
        Write-PreflightResult 'NAT' 'Skip' ('unreadable: ' + $_.Exception.Message)
    }

    try {
        $overlaps = New-Object System.Collections.Generic.List[string]
        $ignore = @('224.0.0.0/4', '255.255.255.255/32') | ForEach-Object { ConvertTo-IPv4Range -Cidr $_ }
        foreach ($r in @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop)) {
            if ($r.DestinationPrefix -eq '0.0.0.0/0' -or $r.InterfaceAlias -eq $cfg.SwitchAdapterAlias) { continue }
            $range = ConvertTo-IPv4Range -Cidr $r.DestinationPrefix
            if (@($ignore | Where-Object { Test-IPv4RangeCover -Outer $_ -Inner $range }).Count -gt 0) { continue }
            if (Test-IPv4RangeOverlap -A $natRange -B $range) { $overlaps.Add(('route {0} via {1}' -f $r.DestinationPrefix, $r.InterfaceAlias)) }
        }
        foreach ($a in @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop)) {
            if ($a.InterfaceAlias -eq $cfg.SwitchAdapterAlias) { continue }
            if (Test-IPv4RangeOverlap -A $natRange -B (ConvertTo-IPv4Range -Cidr $a.IPAddress)) { $overlaps.Add(('address {0} on {1}' -f $a.IPAddress, $a.InterfaceAlias)) }
        }
        if ($overlaps.Count -gt 0) {
            $what = '{0} route(s) or address(es) overlap; re-run with -ShowPrefixes to list them' -f $overlaps.Count
            if ($script:ShowPrefixes) { $what = $overlaps -join '; ' }
            Write-PreflightResult 'NAT prefix overlap' 'Fail' ('{0}: {1}' -f $cfg.NatCidr, $what)
        } else {
            Write-PreflightResult 'NAT prefix overlap' 'Pass' ('{0} does not overlap any route or address' -f $cfg.NatCidr)
        }
    } catch {
        Write-PreflightResult 'NAT prefix overlap' 'Skip' ('unreadable: ' + $_.Exception.Message)
    }

    $isoLen = 0
    $isoOk = $false
    if ($script:IsoSource) {
        try {
            $item = Get-Item -LiteralPath $script:IsoSource -ErrorAction Stop
            $stream = [IO.File]::Open($item.FullName, 'Open', 'Read', 'Read')
            $stream.Close()
            $isoLen = [int64]$item.Length
            if ($isoLen -le 0) { throw 'file is empty' }
            $isoOk = $true
            $level = 'Pass'
            $extra = ''
            if ($item.Extension -ne '.iso') { $level = 'Warn'; $extra = ' (extension is not .iso)' }
            Write-PreflightResult 'Install ISO' $level ('{0}, {1}{2}' -f $item.Name, (Format-HomelabGiB -Bytes $isoLen), $extra)
        } catch {
            Write-PreflightResult 'Install ISO' 'Fail' ('not readable: ' + $_.Exception.Message)
        }
        if ($isoOk -and $script:IsoSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
            Write-PreflightResult 'Install ISO SHA-256' 'Fail' '-InstallIso needs -InstallIsoSha256 (64 hex characters); the hash is verified before the copy and again before the ISO is attached'
        } elseif ($isoOk) {
            Write-PreflightResult 'Install ISO SHA-256' 'Pass' 'expected hash supplied; verified before any change'
        }
    } elseif ($script:WantInstall) {
        Write-PreflightResult 'Install ISO' 'Fail' '-Install needs -InstallIso'
    } else {
        Write-PreflightResult 'Install ISO' 'Warn' 'none supplied; the VM gets an empty DVD drive'
    }

    try {
        $driveRoot = [IO.Path]::GetPathRoot($cfg.RootPath)
        $free = [int64](New-Object IO.DriveInfo $driveRoot).AvailableFreeSpace
        $vhdxNow = 0
        try {
            if (Test-Path -LiteralPath $cfg.VhdxPath) { $vhdxNow = [int64](Get-Item -LiteralPath $cfg.VhdxPath).Length }
        } catch {
            if (-not $script:PlanMode) { throw }
        }
        $isoNeeded = 0
        if ($isoOk) { $isoNeeded = $isoLen }
        $after = $free - ($cfg.DiskBytes - $vhdxNow) - $isoNeeded
        $min = [int64]$cfg.MinFreeDiskAfterGrowthGiB * 1GB
        $text = '{0} free {1}; after full VHDX growth and ISO copy {2} (need {3} GiB)' -f $driveRoot, (Format-HomelabGiB -Bytes $free), (Format-HomelabGiB -Bytes $after), $cfg.MinFreeDiskAfterGrowthGiB
        if ($after -ge $min) { Write-PreflightResult 'Disk' 'Pass' $text } else { Write-PreflightResult 'Disk' 'Fail' $text }
    } catch {
        Write-PreflightResult 'Disk' 'Fail' ('cannot read drive for RootPath: ' + $_.Exception.Message)
    }

    $avail = Get-HomelabAvailableMemory
    $remain = $avail - $cfg.MemoryBytes
    $ramText = 'available {0}; after the VM {1} (need {2} GiB)' -f (Format-HomelabGiB -Bytes $avail), (Format-HomelabGiB -Bytes $remain), $cfg.MinHostFreeRamAfterVmGiB
    if ($remain -ge ([int64]$cfg.MinHostFreeRamAfterVmGiB * 1GB)) { Write-PreflightResult 'RAM' 'Pass' $ramText } else { Write-PreflightResult 'RAM' 'Fail' $ramText }

    $threads = [int](Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    if ($threads -ge $cfg.ProcessorCount) {
        Write-PreflightResult 'CPU' 'Pass' ('{0} logical processors, VM gets {1}' -f $threads, $cfg.ProcessorCount)
    } else {
        Write-PreflightResult 'CPU' 'Fail' ('{0} logical processors, VM wants {1}' -f $threads, $cfg.ProcessorCount)
    }

    if ($script:Rights.Elevated) {
        Write-PreflightResult 'Elevation' 'Pass' 'elevated'
    } elseif ($script:PlanMode) {
        Write-PreflightResult 'Elevation' 'Skip' 'not elevated; plan reads only what works without rights'
    } else {
        Write-PreflightResult 'Elevation' 'Fail' 'run this script from an elevated prompt (it does not self-elevate)'
    }
}

function Assert-PveIsoHash {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$What)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $script:IsoSha256.ToUpperInvariant()) { throw ('{0} SHA-256 mismatch: expected {1}, got {2}. Refusing.' -f $What, $script:IsoSha256.ToUpperInvariant(), $actual) }
}

function Read-PveMarker {
    if (-not (Test-Path -LiteralPath $script:Cfg.MarkerPath)) { return $null }
    Get-Content -LiteralPath $script:Cfg.MarkerPath -Raw | ConvertFrom-Json
}

function Save-PveMarker {
    param([hashtable]$Data)
    $json = $Data | ConvertTo-Json
    Set-Content -LiteralPath $script:Cfg.MarkerPath -Value $json -Encoding ASCII
}

function Invoke-FeatureStep {
    Write-HomelabLog -Level Step -Message 'Step: Hyper-V features'
    if ($script:MissingFeatures.Count -eq 0) { Write-HomelabLog -Level Pass -Message 'already enabled'; return $false }
    if ($script:PlanMode) { Write-HomelabLog -Level Plan -Message ('enable {0} with -NoRestart, then stop with exit code 2' -f ($script:MissingFeatures -join ', ')); return $false }
    $reboot = $false
    if ([int](Get-CimInstance -ClassName Win32_OperatingSystem).ProductType -eq 1) {
        $r = Enable-WindowsOptionalFeature -Online -FeatureName 'Microsoft-Hyper-V-All' -All -NoRestart
        if ($r.RestartNeeded) { $reboot = $true }
    } else {
        $r = Install-WindowsFeature -Name Hyper-V -IncludeManagementTools
        if ([string]$r.RestartNeeded -ne 'No') { $reboot = $true }
    }
    if (-not $reboot -and -not (Get-Service -Name vmms -ErrorAction SilentlyContinue)) { $reboot = $true }
    $reboot
}

function Invoke-RootStep {
    $cfg = $script:Cfg
    Write-HomelabLog -Level Step -Message ('Step: VM folder and ACL ({0})' -f $cfg.RootPath)
    $acl = Get-PveRootAclSpec | ForEach-Object { '{0}:{1}' -f $_.Label, $_.Rights }
    Assert-PveSafePath -Config $cfg -Lenient:$script:PlanMode
    if ($script:PlanMode) {
        if (Test-Path -LiteralPath $cfg.RootPath) {
            Write-HomelabLog -Level Plan -Message ('folder exists; verify marker and protected ACL ({0})' -f ($acl -join '; '))
        } else {
            Write-HomelabLog -Level Plan -Message ('create folder with protected ACL, inheritance off ({0})' -f ($acl -join '; '))
        }
        return
    }
    if (Test-Path -LiteralPath $cfg.RootPath) {
        $hasMarker = Test-Path -LiteralPath $cfg.MarkerPath
        $empty = @(Get-ChildItem -LiteralPath $cfg.RootPath -Force -ErrorAction SilentlyContinue).Count -eq 0
        if (-not $hasMarker -and -not $empty) { throw "RootPath $($cfg.RootPath) exists, is not empty and was not created by this script (no marker). Refusing to adopt it." }
    } else {
        New-Item -ItemType Directory -Path $cfg.RootPath -Force | Out-Null
    }
    if (-not (Test-PveRootAcl -Path $cfg.RootPath)) {
        Initialize-PveRootAcl -Path $cfg.RootPath
        Write-HomelabLog -Level Pass -Message ('protected ACL applied: ' + ($acl -join '; '))
    } else {
        Write-HomelabLog -Level Pass -Message 'protected ACL already in place'
    }
    if (-not (Test-Path -LiteralPath $cfg.MarkerPath)) {
        Save-PveMarker -Data @{ vmName = $cfg.VmName; createdUtc = (Get-Date).ToUniversalTime().ToString('s'); groupMemberAdded = $null }
    }
}

function Invoke-MembershipStep {
    Write-HomelabLog -Level Step -Message 'Step: Hyper-V Administrators membership (group SID S-1-5-32-578)'
    $rights = Get-HomelabHyperVRight
    if (-not $script:Cfg.AddOwnerToHyperVAdministrators) {
        Write-HomelabLog -Level Skip -Message 'AddOwnerToHyperVAdministrators is false: the current user is not added. Invoke-PveVm.ps1 then needs an elevated prompt for every action.'
        return
    }
    if ($script:PlanMode) {
        Write-HomelabLog -Level Plan -Message 'add the current user (resolved by SID) to the group if missing; effective after the next sign-in'
        Write-HomelabLog -Level Info -Message ('currently: member={0}, group in this token={1}' -f $rights.MemberConfigured, $rights.InHyperVAdminsToken)
        return
    }
    $res = Grant-PveCurrentUserHyperVAdmin
    if ($res.Result -eq 'Added') {
        Write-HomelabLog -Level Pass -Message ("added user {0} to '{1}'; this applies after the next sign-in" -f $res.UserSid, $res.Group)
        $marker = Read-PveMarker
        if ($marker) { Save-PveMarker -Data @{ vmName = $marker.vmName; createdUtc = $marker.createdUtc; groupMemberAdded = $res.UserSid } }
    } else {
        Write-HomelabLog -Level Pass -Message ("already a member of '{0}'; if Hyper-V cmdlets are still denied in a normal prompt, sign out and in" -f $res.Group)
    }
}

function Invoke-IsoStep {
    $cfg = $script:Cfg
    Write-HomelabLog -Level Step -Message 'Step: install ISO copy'
    if (-not $script:IsoSource) { Write-HomelabLog -Level Skip -Message 'no -InstallIso supplied'; return }
    $src = (Resolve-Path -LiteralPath $script:IsoSource).ProviderPath
    $dest = Join-Path $cfg.RootPath (Split-Path -Leaf $src)
    $script:IsoDest = $dest
    if ($script:PlanMode) { Write-HomelabLog -Level Plan -Message ('verify the source SHA-256 against -InstallIsoSha256, copy {0} to {1}, verify the copy again' -f $src, $dest); return }
    Assert-PveSafePath -Config $cfg
    Assert-PveIsoHash -Path $src -What 'source ISO'
    if ($src -eq $dest) { Write-HomelabLog -Level Pass -Message 'ISO already inside RootPath, hash verified'; return }
    if ((Test-Path -LiteralPath $dest) -and (Get-Item -LiteralPath $dest).Length -eq (Get-Item -LiteralPath $src).Length -and (Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -eq $script:IsoSha256.ToUpperInvariant()) {
        Write-HomelabLog -Level Pass -Message ('copy already present, SHA-256 {0}' -f $script:IsoSha256.ToUpperInvariant())
        $script:IsoCopied = $true
        return
    }
    Copy-Item -LiteralPath $src -Destination $dest -Force
    $script:IsoCopied = $true
    Assert-PveIsoHash -Path $dest -What 'ISO copy under RootPath'
    Write-HomelabLog -Level Pass -Message ('copied and verified, SHA-256 {0}' -f $script:IsoSha256.ToUpperInvariant())
}

function Invoke-NetworkStep {
    $cfg = $script:Cfg
    $alias = $cfg.SwitchAdapterAlias
    $natRange = ConvertTo-IPv4Range -Cidr $cfg.NatPrefix
    Write-HomelabLog -Level Step -Message 'Step: internal switch, host address, NAT'
    if ($script:PlanMode) {
        if ($script:Rights.HasRights) {
            $sw = Get-VMSwitch -Name $cfg.SwitchName -ErrorAction SilentlyContinue
            if ($sw) { Write-HomelabLog -Level Plan -Message ("switch '{0}' exists (type {1}); verify type is Internal" -f $cfg.SwitchName, $sw.SwitchType) } else { Write-HomelabLog -Level Plan -Message ("create Internal switch '{0}'" -f $cfg.SwitchName) }
        } else {
            Write-HomelabLog -Level Plan -Message ("ensure Internal switch '{0}' ({1})" -f $cfg.SwitchName, $script:NeedsRightsText)
        }
        Write-HomelabLog -Level Plan -Message ('ensure {0}/{1} on "{2}", DHCP off, no gateway' -f $cfg.HostAddress, $natRange.PrefixLength, $alias)
        Write-HomelabLog -Level Plan -Message ("ensure NetNat '{0}' on {1}; no port mappings are created" -f $cfg.NatName, $cfg.NatCidr)
        Write-HomelabLog -Level Plan -Message ('disable the IPv6 binding (ms_tcpip6) on "{0}" so the host has no IPv6 listener on the guest segment' -f $alias)
        return
    }
    $sw = Get-VMSwitch -Name $cfg.SwitchName -ErrorAction SilentlyContinue
    if ($sw) {
        if ([string]$sw.SwitchType -ne 'Internal') { throw "Switch '$($cfg.SwitchName)' exists but is type $($sw.SwitchType), not Internal" }
        Write-HomelabLog -Level Pass -Message 'switch already present'
    } else {
        New-VMSwitch -Name $cfg.SwitchName -SwitchType Internal | Out-Null
        Write-HomelabLog -Level Pass -Message 'switch created'
    }
    $waited = 0
    while (-not (Get-NetAdapter -Name $alias -ErrorAction SilentlyContinue)) {
        if ($waited -ge 30) { throw "Host adapter '$alias' did not appear" }
        Start-Sleep -Seconds 1
        $waited++
    }
    $v6 = Get-NetAdapterBinding -Name $alias -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    if ($v6 -and $v6.Enabled) {
        Disable-NetAdapterBinding -Name $alias -ComponentID ms_tcpip6 -Confirm:$false
        Write-HomelabLog -Level Pass -Message 'IPv6 binding disabled on the host vEthernet'
    } else {
        Write-HomelabLog -Level Pass -Message 'IPv6 binding already disabled (or not readable)'
    }
    Set-NetIPInterface -InterfaceAlias $alias -AddressFamily IPv4 -Dhcp Disabled
    $ips = @(Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue)
    foreach ($ip in $ips) {
        if ($ip.IPAddress -ne $cfg.HostAddress -or $ip.PrefixLength -ne $natRange.PrefixLength) {
            Remove-NetIPAddress -InterfaceAlias $alias -IPAddress $ip.IPAddress -Confirm:$false
        }
    }
    if (@($ips | Where-Object { $_.IPAddress -eq $cfg.HostAddress -and $_.PrefixLength -eq $natRange.PrefixLength }).Count -eq 0) {
        New-NetIPAddress -InterfaceAlias $alias -IPAddress $cfg.HostAddress -PrefixLength $natRange.PrefixLength | Out-Null
        Write-HomelabLog -Level Pass -Message ('host address {0}/{1} set' -f $cfg.HostAddress, $natRange.PrefixLength)
    } else {
        Write-HomelabLog -Level Pass -Message 'host address already set'
    }
    $nats = @(Get-NetNat -ErrorAction SilentlyContinue)
    if (@($nats | Where-Object { $_.Name -ne $cfg.NatName }).Count -gt 0) { throw 'A foreign NAT exists; WinNAT allows one NAT per host. Not touching it.' }
    $ours = @($nats | Where-Object { $_.Name -eq $cfg.NatName })
    if ($ours.Count -gt 0) {
        if ($ours[0].InternalIPInterfaceAddressPrefix -ne $cfg.NatCidr) { throw "NAT '$($cfg.NatName)' has prefix $($ours[0].InternalIPInterfaceAddressPrefix), config wants $($cfg.NatCidr)" }
        Write-HomelabLog -Level Pass -Message 'NAT already present'
    } else {
        New-NetNat -Name $cfg.NatName -InternalIPInterfaceAddressPrefix $cfg.NatCidr | Out-Null
        Write-HomelabLog -Level Pass -Message 'NAT created'
    }
}

function Get-PveVmDrift {
    $cfg = $script:Cfg
    $n = $cfg.VmName
    $vm = Get-VM -Name $n
    $proc = Get-VMProcessor -VMName $n
    $mem = Get-VMMemory -VMName $n
    $fw = Get-VMFirmware -VMName $n
    $nic = Get-PveVmAdapter -Config $cfg
    $items = New-Object System.Collections.Generic.List[object]
    $note = {
        param($Item, $Want, $Have, $Fix)
        if ([string]$Want -ne [string]$Have) { $items.Add([pscustomobject]@{ Item = $Item; Want = [string]$Want; Have = [string]$Have; Fix = $Fix }) }
    }
    $memFix = { Set-VMMemory -VMName $n -DynamicMemoryEnabled $false -StartupBytes $cfg.MemoryBytes }.GetNewClosure()
    $vmFix = { Set-VM -Name $n -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -AutomaticCheckpointsEnabled $false -CheckpointType Standard }.GetNewClosure()
    $macFix = { Set-VMNetworkAdapter -VMNetworkAdapter $nic -StaticMacAddress $cfg.MacPlain }.GetNewClosure()
    $guardFix = { Set-VMNetworkAdapter -VMNetworkAdapter $nic -MacAddressSpoofing Off -DhcpGuard On -RouterGuard On }.GetNewClosure()
    $cpuFix = { Set-VMProcessor -VMName $n -Count $cfg.ProcessorCount }.GetNewClosure()
    $nestedFix = { Set-VMProcessor -VMName $n -ExposeVirtualizationExtensions $true }.GetNewClosure()
    $bootFirmwareFix = { Set-VMFirmware -VMName $n -EnableSecureBoot Off }.GetNewClosure()
    $bootFix = {
        $hdd = @(Get-VMHardDiskDrive -VMName $n)[0]
        $dvd = @(Get-VMDvdDrive -VMName $n)[0]
        Set-VMFirmware -VMName $n -BootOrder $hdd, $dvd
    }.GetNewClosure()
    $hdd = @(Get-VMHardDiskDrive -VMName $n)
    $hddPath = ''
    if ($hdd.Count -gt 0) { $hddPath = [string]$hdd[0].Path }
    $order = @($fw.BootOrder)
    $bootCurrent = 'other'
    if ($order.Count -eq 2 -and $order[0].Device -and [string]$order[0].Device.Path -eq $cfg.VhdxPath) { $bootCurrent = 'disk,dvd' }

    & $note 'Generation' 2 $vm.Generation $null
    & $note 'ProcessorCount' $cfg.ProcessorCount $proc.Count $cpuFix
    & $note 'ExposeVirtualizationExtensions' $true $proc.ExposeVirtualizationExtensions $nestedFix
    & $note 'DynamicMemoryEnabled' $false $mem.DynamicMemoryEnabled $memFix
    & $note 'StartupMemoryBytes' $cfg.MemoryBytes $mem.Startup $memFix
    & $note 'SecureBoot' 'Off' $fw.SecureBoot $bootFirmwareFix
    & $note 'AutomaticStartAction' 'Nothing' $vm.AutomaticStartAction $vmFix
    & $note 'AutomaticStopAction' 'ShutDown' $vm.AutomaticStopAction $vmFix
    & $note 'AutomaticCheckpointsEnabled' $false $vm.AutomaticCheckpointsEnabled $vmFix
    & $note 'CheckpointType' 'Standard' $vm.CheckpointType $vmFix
    & $note 'DynamicMacAddressEnabled' $false $nic.DynamicMacAddressEnabled $macFix
    & $note 'MacAddress' $cfg.MacPlain $nic.MacAddress $macFix
    & $note 'MacAddressSpoofing' 'Off' $nic.MacAddressSpoofing $guardFix
    & $note 'DhcpGuard' 'On' $nic.DhcpGuard $guardFix
    & $note 'RouterGuard' 'On' $nic.RouterGuard $guardFix
    & $note 'BootOrder' 'disk,dvd' $bootCurrent $bootFix
    & $note 'DiskPath' $cfg.VhdxPath $hddPath $null
    $items.ToArray()
}

function Invoke-VmStep {
    $cfg = $script:Cfg
    $n = $cfg.VmName
    Write-HomelabLog -Level Step -Message ("Step: VM '{0}'" -f $n)
    $desc = 'Gen2, {0} vCPU, {1} GiB static memory, dynamic VHDX max {2} GiB, Secure Boot off, nested virtualization on, MAC {3}, spoofing off, auto checkpoints off, boot order disk then DVD' -f $cfg.ProcessorCount, $cfg.MemoryGiB, $cfg.DiskGiB, $cfg.MacAddress
    if ($script:PlanMode) {
        if (-not $script:Rights.HasRights) { Write-HomelabLog -Level Plan -Message ("ensure VM: {0} ({1})" -f $desc, $script:NeedsRightsText); return }
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { Write-HomelabLog -Level Plan -Message ('create VM: ' + $desc); return }
        Write-HomelabLog -Level Plan -Message ('VM exists (state {0}); reconcile only while Off, otherwise report drift' -f $vm.State)
        foreach ($d in @(Get-PveVmDrift)) { Write-HomelabLog -Level Warn -Message ('drift {0}: have {1}, want {2}' -f $d.Item, $d.Have, $d.Want) }
        return
    }
    $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
    $created = $false
    if ($vm) {
        if (-not (Test-PveInsideRoot -Path $vm.Path -Root $cfg.RootPath)) { throw "VM '$n' exists outside RootPath ($($vm.Path)); not touching it." }
    } else {
        New-VM -Name $n -Generation 2 -MemoryStartupBytes $cfg.MemoryBytes -NewVHDPath $cfg.VhdxPath -NewVHDSizeBytes $cfg.DiskBytes -Path $cfg.RootPath | Out-Null
        $created = $true
        Write-HomelabLog -Level Pass -Message 'VM created'
        $vm = Get-VM -Name $n
    }
    if (@(Get-VMNetworkAdapter -VMName $n).Count -eq 0) { Add-VMNetworkAdapter -VMName $n }
    if ($vm.State -eq 'Off' -and @(Get-VMDvdDrive -VMName $n).Count -eq 0) { Add-VMDvdDrive -VMName $n }
    $drift = @(Get-PveVmDrift)
    if ($drift.Count -eq 0) {
        Write-HomelabLog -Level Pass -Message 'VM settings match the config'
    } elseif ($vm.State -eq 'Off') {
        foreach ($f in @($drift | Where-Object { $_.Fix } | ForEach-Object { $_.Fix } | Select-Object -Unique)) { & $f }
        foreach ($d in $drift) {
            if ($d.Fix) { Write-HomelabLog -Level Pass -Message ('set {0}: {1} -> {2}' -f $d.Item, $d.Have, $d.Want) } else { Write-HomelabLog -Level Fail -Message ('drift {0}: have {1}, want {2} (not fixable in place)' -f $d.Item, $d.Have, $d.Want); $script:Failures++ }
        }
        $left = @(Get-PveVmDrift)
        if (@($left | Where-Object { $_.Item -eq 'BootOrder' }).Count -gt 0) { Write-HomelabLog -Level Warn -Message 'boot order could not be confirmed from the read-back; check it in Hyper-V Manager (disk first, DVD second)' }
        $hard = @($left | Where-Object { $_.Item -ne 'BootOrder' })
        if ($hard.Count -gt 0) { throw ('VM settings still differ after reconcile: ' + (($hard | ForEach-Object { $_.Item }) -join ', ')) }
    } else {
        foreach ($d in $drift) { Write-HomelabLog -Level Warn -Message ('drift {0}: have {1}, want {2} (VM is {3}, not changed)' -f $d.Item, $d.Have, $d.Want, $vm.State) }
    }
    if ($script:IsoDest -and ($created -or $script:WantInstall) -and $vm.State -eq 'Off') {
        Assert-PveIsoHash -Path $script:IsoDest -What 'ISO copy before attach'
        Set-VMDvdDrive -VMName $n -Path $script:IsoDest
        Write-HomelabLog -Level Pass -Message ('ISO attached: ' + $script:IsoDest)
    }
}

function Invoke-IsolationStep {
    $cfg = $script:Cfg
    Write-HomelabLog -Level Step -Message 'Step: host-side isolation (port ACLs + Windows Firewall rule)'
    $spec = Get-PveFirewallRuleSpec -Config $cfg
    $fwText = 'Block inbound from {0} on "{1}", all profiles (rule {2})' -f $spec.RemoteAddress, $spec.InterfaceAlias, $spec.Name
    if ($script:PlanMode) {
        $in = Get-PveDenyInput -Config $cfg
        $state = 'absent'
        if (Test-Path -LiteralPath $cfg.LocalOverridePath) { $state = 'present' }
        Write-HomelabLog -Level Info -Message ('local override {0}: {1}' -f $cfg.LocalOverridePath, $state)
        Write-PveDenySummary -DenyInput $in -ShowPrefixes:$script:ShowPrefixes
        if (@($in.AliasToRecord).Count -gt 0) { Write-HomelabLog -Level Plan -Message ('would record EgressInterfaceAlias = {0} in the local override' -f (@($in.AliasToRecord) -join ', ')) }
        $plan = @(Get-PveAclPlan -Config $cfg -ExtraDenyPrefix $in.Extra -DenyAllEgress:$in.DenyAll)
        Write-HomelabLog -Level Plan -Message ("port ACL table the VM adapter would get (larger weight applies first; host-routed prefixes are masked unless -ShowPrefixes):`n" + (Format-PveAclTable -Rule $plan -Config $cfg -ShowPrefixes:$script:ShowPrefixes))
        Write-HomelabLog -Level Plan -Message 'refuse if any extended ACL exists outside the reserved weight range'
        Write-HomelabLog -Level Plan -Message ('firewall: ' + $fwText)
        return
    }
    $r = Sync-PveIsolation -Config $cfg -Persist -ShowPrefixes:$script:ShowPrefixes
    $res = $r.Result
    Write-HomelabLog -Level Pass -Message ("port ACLs applied (added {0}, removed {1}). Intent:`n{2}" -f $res.Added, $res.Removed, (Format-PveAclTable -Rule $res.Desired -Config $cfg -ShowPrefixes:$script:ShowPrefixes))
    Write-HomelabLog -Level Info -Message ("Read back from Hyper-V:`n" + (Format-PveAclTable -Rule $res.Applied -Config $cfg -ShowPrefixes:$script:ShowPrefixes))
    $fwResult = Sync-PveHostFirewallRule -Config $cfg
    Write-HomelabLog -Level Pass -Message ('firewall rule {0}: {1}' -f $fwResult, $fwText)
    if ((Get-PveFirewallState -Config $cfg) -ne 'present') {
        Disconnect-VMNetworkAdapter -VMName $cfg.VmName
        throw 'The Windows Firewall rule is not in place after sync; the adapter was disconnected.'
    }
}

function Invoke-ConnectStep {
    $cfg = $script:Cfg
    Write-HomelabLog -Level Step -Message 'Step: connect the VM adapter (only after the port ACLs and the firewall rule check out)'
    if ($script:PlanMode) { Write-HomelabLog -Level Plan -Message ("connect the adapter to '{0}' if it is not connected" -f $cfg.SwitchName); return }
    $nic = Get-PveVmAdapter -Config $cfg
    if ($nic.SwitchName -eq $cfg.SwitchName) {
        Write-HomelabLog -Level Pass -Message 'adapter already connected'
    } else {
        Connect-VMNetworkAdapter -VMNetworkAdapter $nic -SwitchName $cfg.SwitchName
        Write-HomelabLog -Level Pass -Message ("adapter connected to '{0}'" -f $cfg.SwitchName)
    }
}

function Invoke-FileAccessStep {
    Write-HomelabLog -Level Step -Message 'Step: per-VM file access check'
    if (-not $script:PlanMode) { Assert-PveSafePath -Config $script:Cfg }
    if ($script:PlanMode) { Write-HomelabLog -Level Plan -Message 'verify the per-VM account has an ACE on the VHDX, ISO copy and config; grant it with icacls if absent'; return }
    foreach ($r in @(Confirm-PveVmFileAccess -Config $script:Cfg)) {
        if ($r.GrantedNow) { Write-HomelabLog -Level Info -Message ('per-VM ACE not found in the ACL read-back, granted (idempotent): ' + $r.File) } else { Write-HomelabLog -Level Pass -Message ('per-VM ACE present: ' + $r.File) }
    }
}

function Test-InstallGuard {
    $cfg = $script:Cfg
    $limit = [int64]$cfg.EmptyVhdxMaxMiB * 1MB
    try {
        if (Test-Path -LiteralPath $cfg.VhdxPath) {
            $len = (Get-Item -LiteralPath $cfg.VhdxPath).Length
            if ($len -gt $limit) { return ('VHDX {0} is {1} bytes (limit {2}); it holds data. Never reinstall over data.' -f $cfg.VhdxPath, $len, $limit) }
        }
    } catch {
        if (-not $script:PlanMode) { throw }
        Write-HomelabLog -Level Skip -Message 'VHDX size: needs elevation/Hyper-V rights - skipped in plan'
    }
    if (-not $script:Rights.HasRights) { return $null }
    $vm = Get-VM -Name $cfg.VmName -ErrorAction SilentlyContinue
    if ($vm) {
        if ($vm.State -ne 'Off') { return ('VM is {0}; -Install needs it Off and untouched.' -f $vm.State) }
        if (@(Get-VMSnapshot -VMName $cfg.VmName -ErrorAction SilentlyContinue).Count -gt 0) { return 'VM has checkpoints; it was installed before. Never reinstall over data.' }
    }
    $null
}

function Invoke-InstallStep {
    $cfg = $script:Cfg
    $n = $cfg.VmName
    Write-HomelabLog -Level Step -Message 'Step: unattended install, checkpoint, first cold start'
    if ($script:PlanMode) {
        Write-HomelabLog -Level Plan -Message ('start VM; wait until Off (timeout {0} min, progress every {1} s); eject the ISO (documented form, confirmed by read-back); Checkpoint-VM "{2}" while Off; start; wait for TCP {3}:{4} (timeout {5} min); print elapsed seconds; then delete the ISO copy under RootPath (it holds the root-password hash)' -f $cfg.InstallTimeoutMinutes, $cfg.ProgressSeconds, $cfg.CheckpointName, $cfg.GuestAddress, $cfg.SshPort, $cfg.BootTimeoutMinutes)
        return 0
    }
    $limit = [int64]$cfg.EmptyVhdxMaxMiB * 1MB
    $clock = [Diagnostics.Stopwatch]::StartNew()
    Sync-PveIsolation -Config $cfg -Persist -ShowPrefixes:$script:ShowPrefixes | Out-Null
    Start-VM -Name $n
    Write-HomelabLog -Level Info -Message 'install started; the answer file must power the VM off when done'
    while ($true) {
        Start-Sleep -Seconds $cfg.ProgressSeconds
        $v = Get-VM -Name $n
        Write-HomelabLog -Level Info -Message ('install: state {0}, elapsed {1} s, cpu {2}%, vhdx {3}' -f $v.State, [int]$clock.Elapsed.TotalSeconds, $v.CPUUsage, (Format-HomelabGiB -Bytes (Get-Item -LiteralPath $cfg.VhdxPath).Length))
        if ($v.State -eq 'Off') { break }
        if ($clock.Elapsed.TotalMinutes -ge $cfg.InstallTimeoutMinutes) {
            Write-HomelabLog -Level Fail -Message ('install did not finish within {0} min; the VM is left as is for inspection' -f $cfg.InstallTimeoutMinutes)
            return 1
        }
    }
    if ((Get-Item -LiteralPath $cfg.VhdxPath).Length -le $limit) {
        Write-HomelabLog -Level Fail -Message 'VM powered off but the VHDX is still empty; the install did not complete. No checkpoint taken.'
        return 1
    }
    foreach ($d in @(Get-VMDvdDrive -VMName $n | Where-Object { $_.Path })) {
        Set-VMDvdDrive -VMName $n -ControllerNumber $d.ControllerNumber -ControllerLocation $d.ControllerLocation -Path $null
    }
    $ejected = $false
    for ($t = 0; $t -le 20; $t++) {
        if (@(Get-VMDvdDrive -VMName $n | Where-Object { $_.Path }).Count -eq 0) { $ejected = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ejected) {
        Write-HomelabLog -Level Fail -Message 'ISO still attached 20 s after the eject; no checkpoint taken and the ISO copy is kept. Eject it by hand (Set-VMDvdDrive -VMName <vm> -ControllerNumber <n> -ControllerLocation <m> -Path $null) and re-run.'
        return 1
    }
    Write-HomelabLog -Level Pass -Message 'ISO ejected (confirmed by read-back)'
    Checkpoint-VM -Name $n -SnapshotName $cfg.CheckpointName
    Write-HomelabLog -Level Pass -Message ('checkpoint "{0}" taken while Off, without the ISO attached' -f $cfg.CheckpointName)
    Sync-PveIsolation -Config $cfg -Persist -ShowPrefixes:$script:ShowPrefixes | Out-Null
    $boot = [Diagnostics.Stopwatch]::StartNew()
    Start-VM -Name $n
    $secs = Wait-PveTcpPort -Address $cfg.GuestAddress -Port $cfg.SshPort -TimeoutSeconds ($cfg.BootTimeoutMinutes * 60) -Clock $boot -ProgressSeconds $cfg.ProgressSeconds
    if ($null -eq $secs) {
        Write-HomelabLog -Level Fail -Message ('TCP {0}:{1} did not answer within {2} min of the first boot from disk' -f $cfg.GuestAddress, $cfg.SshPort, $cfg.BootTimeoutMinutes)
        return 1
    }
    Write-HomelabLog -Level Pass -Message ('first cold start: TCP {0}:{1} answered {2} s after Start-VM' -f $cfg.GuestAddress, $cfg.SshPort, $secs)
    if ($script:IsoCopied -and $script:IsoDest -and (Test-Path -LiteralPath $script:IsoDest) -and (Test-PveInsideRoot -Path $script:IsoDest -Root $cfg.RootPath)) {
        Assert-PveSafePath -Config $cfg
        [IO.File]::Delete($script:IsoDest)
        Write-HomelabLog -Level Pass -Message ('install ISO copy deleted from the VM folder (it held the root-password hash): ' + (Split-Path -Leaf $script:IsoDest))
    }
    Write-HomelabLog -Level Info -Message 'Reminder: delete the source ISO you passed with -InstallIso (it also holds the root-password hash). This script never touches it.'
    0
}

function Invoke-UninstallFlow {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([int])]
    param()
    $cfg = $script:Cfg
    $n = $cfg.VmName
    $marker = $null
    if (Test-Path -LiteralPath $cfg.MarkerPath) { $marker = Read-PveMarker }
    $list = @(
        ("VM '{0}' (and its checkpoints)" -f $n)
        ('known files in {0} (*.vhdx, *.avhdx, *.iso, the VM config files by VM id, the marker), then empty folders only; anything else is left and counted' -f $cfg.RootPath)
        ("NetNat '{0}' ({1})" -f $cfg.NatName, $cfg.NatCidr)
        ("Internal switch '{0}'" -f $cfg.SwitchName)
        ("firewall rule '{0}'" -f $cfg.FirewallRuleName)
        'Hyper-V Administrators membership, only if this script added it for the account running this command'
    )
    Write-HomelabLog -Level Step -Message 'Uninstall'
    foreach ($l in $list) { Write-HomelabLog -Level Plan -Message ('remove ' + $l) }
    if ($script:PlanMode) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($env:COMPUTERNAME, 'Remove: ' + ($list -join '; '))) { Write-HomelabLog -Level Info -Message 'cancelled'; return 0 }
    try {
        Assert-PveSafePath -Config $cfg
    } catch {
        Write-HomelabLog -Level Fail -Message $_.Exception.Message
        return 1
    }

    $errors = 0
    $script:UninstallVmId = $null
    $steps = [ordered]@{}
    $steps['VM'] = {
        $vm = Get-VM -Name $n -ErrorAction SilentlyContinue
        if (-not $vm) { return 'absent' }
        if (-not (Test-PveInsideRoot -Path $vm.Path -Root $cfg.RootPath)) { return "skipped: VM '$n' lives outside RootPath" }
        $script:UninstallVmId = $vm.Id.ToString()
        if ($vm.State -ne 'Off') { Stop-VM -Name $n -TurnOff -Force }
        Remove-VM -Name $n -Force
        'removed'
    }
    $steps['Firewall rule'] = { if (Revoke-PveHostFirewallRule -Config $cfg) { 'removed' } else { 'absent' } }
    $steps['NAT'] = {
        $nat = @(Get-NetNat -Name $cfg.NatName -ErrorAction SilentlyContinue)
        if ($nat.Count -eq 0) { return 'absent' }
        if ($nat[0].InternalIPInterfaceAddressPrefix -ne $cfg.NatCidr) { return 'skipped: prefix differs from config' }
        Remove-NetNat -Name $cfg.NatName -Confirm:$false
        'removed'
    }
    $steps['Switch'] = {
        $sw = Get-VMSwitch -Name $cfg.SwitchName -ErrorAction SilentlyContinue
        if (-not $sw) { return 'absent' }
        if ([string]$sw.SwitchType -ne 'Internal') { return 'skipped: not an Internal switch' }
        if (@(Get-VMNetworkAdapter -All -ErrorAction SilentlyContinue | Where-Object { $_.SwitchName -eq $cfg.SwitchName }).Count -gt 0) { return 'skipped: another adapter is still connected' }
        Remove-VMSwitch -Name $cfg.SwitchName -Force
        'removed'
    }
    $steps['Folder'] = {
        if (-not (Test-Path -LiteralPath $cfg.RootPath)) { return 'absent' }
        if (-not $marker -or $marker.vmName -ne $cfg.VmName) { return 'skipped: no matching script marker in the folder, not deleting anything' }
        $files = New-Object System.Collections.Generic.List[string]
        foreach ($f in @(Get-ChildItem -LiteralPath $cfg.RootPath -File -Force)) {
            if (@('.vhdx', '.avhdx', '.iso') -contains $f.Extension.ToLowerInvariant() -or $f.FullName -eq $cfg.MarkerPath) { $files.Add($f.FullName) }
        }
        $vmDir = Join-Path $cfg.RootPath $cfg.VmName
        if ($script:UninstallVmId) {
            $cfgDir = Join-Path $vmDir 'Virtual Machines'
            if (Test-Path -LiteralPath $cfgDir) {
                foreach ($f in @(Get-ChildItem -LiteralPath $cfgDir -File -Force | Where-Object { $_.Name.StartsWith($script:UninstallVmId, [StringComparison]::OrdinalIgnoreCase) })) { $files.Add($f.FullName) }
            }
        }
        foreach ($f in $files) { Remove-Item -LiteralPath $f -Force }
        $dirs = New-Object System.Collections.Generic.List[string]
        $pending = New-Object System.Collections.Generic.Queue[string]
        $pending.Enqueue($cfg.RootPath)
        while ($pending.Count -gt 0) {
            $d = $pending.Dequeue()
            foreach ($c in @(Get-ChildItem -LiteralPath $d -Directory -Force)) { $dirs.Add($c.FullName); $pending.Enqueue($c.FullName) }
        }
        $removedDirs = 0
        foreach ($d in @($dirs | Sort-Object { $_.Length } -Descending) + @($cfg.RootPath)) {
            if (@(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) { [IO.Directory]::Delete($d); $removedDirs++ }
        }
        $left = 0
        if (Test-Path -LiteralPath $cfg.RootPath) { $left = @(Get-ChildItem -LiteralPath $cfg.RootPath -Recurse -Force -File).Count }
        'removed {0} file(s) and {1} folder(s); {2} unexpected file(s) left in place' -f $files.Count, $removedDirs, $left
    }
    $steps['Group membership'] = {
        if (-not $marker -or -not $marker.groupMemberAdded) { return 'left as is (this script did not add it, or the marker is gone)' }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ([string]$marker.groupMemberAdded -ne $me) { return 'left as is (the marker SID is not the account running this command)' }
        if (Revoke-PveUserHyperVAdmin -UserSid $me) { 'removed; applies after the next sign-in' } else { 'absent' }
    }
    foreach ($k in $steps.Keys) {
        try {
            $r = & $steps[$k]
            Write-HomelabLog -Level Pass -Message ('{0}: {1}' -f $k, $r)
        } catch {
            $errors++
            Write-HomelabLog -Level Fail -Message ('{0}: {1}' -f $k, $_.Exception.Message)
        }
    }
    if ($errors -gt 0) { return 1 }
    0
}

function Invoke-Main {
    $script:Cfg = Import-PveConfig -Path $ConfigPath
    $cfg = $script:Cfg
    $script:Rights = Get-HomelabHyperVRight
    if ($script:PlanMode) {
        Write-HomelabLog -Level Step -Message ('PLAN ONLY - nothing is changed. Config: {0}' -f $cfg.ConfigFile)
    } else {
        if (-not $script:Rights.Elevated) {
            Write-HomelabLog -Level Fail -Message 'This script must run from an elevated prompt (it does not self-elevate). Use -PlanOnly to preview without elevation.'
            return 1
        }
        $logDir = Join-Path $env:LOCALAPPDATA 'homelab\logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $log = Join-Path $logDir ('New-PveHost-{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
        Start-Transcript -Path $log | Out-Null
        Write-HomelabLog -Level Info -Message ('transcript: ' + $log)
    }
    try {
        if ($script:UninstallRequested) { return (Invoke-UninstallFlow) }

        Invoke-Preflight
        if ($script:Failures -gt 0) {
            Write-HomelabLog -Level Fail -Message ('{0} preflight check(s) failed; nothing was changed.' -f $script:Failures)
            return 1
        }
        if ($script:IsoSource -and -not $script:PlanMode) {
            Assert-PveIsoHash -Path (Resolve-Path -LiteralPath $script:IsoSource).ProviderPath -What 'source ISO'
            Write-HomelabLog -Level Pass -Message 'source ISO SHA-256 matches -InstallIsoSha256'
        }
        if ($script:WantInstall) {
            $guard = Test-InstallGuard
            if ($guard) { Write-HomelabLog -Level Fail -Message ('-Install refused: ' + $guard); return 1 }
        }
        if (Invoke-FeatureStep) {
            Write-HomelabLog -Level Warn -Message 'A reboot is needed to finish enabling Hyper-V. This script never reboots. Restart Windows yourself, then run it again.'
            return 2
        }
        Invoke-RootStep
        Invoke-MembershipStep
        Invoke-IsoStep
        Invoke-NetworkStep
        Invoke-VmStep
        Invoke-IsolationStep
        Invoke-ConnectStep
        Invoke-FileAccessStep
        $code = 0
        if ($script:WantInstall) { $code = @(Invoke-InstallStep)[-1] }
        if ($script:Failures -gt 0) { $code = 1 }
        if ($script:PlanMode) {
            Write-HomelabLog -Level Step -Message 'Plan complete. Nothing was changed.'
        } elseif ($code -eq 0) {
            Write-HomelabLog -Level Step -Message 'Done.'
            if (-not $script:WantInstall) { Write-HomelabLog -Level Info -Message 'The VM is created but not started. Re-run with -Install and -InstallIso for the unattended install.' }
        }
        return $code
    } finally {
        if (-not $script:PlanMode) { Stop-Transcript | Out-Null }
    }
}

$exitCode = 1
try {
    $exitCode = @(Invoke-Main)[-1]
} catch {
    Write-HomelabLog -Level Fail -Message $_.Exception.Message
    Write-HomelabLog -Level Info -Message $_.ScriptStackTrace
}
exit $exitCode
