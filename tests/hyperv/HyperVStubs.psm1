$specs = [ordered]@{
    'Get-NetRoute'                      = 'AddressFamily'
    'Get-VM'                            = 'Name,Id'
    'Get-VMNetworkAdapter'              = 'VMName'
    'Get-VMNetworkAdapterExtendedAcl'   = 'VMName'
    'Add-VMNetworkAdapterExtendedAcl'   = 'VMNetworkAdapter,Action,Direction,Weight,RemoteIPAddress,LocalIPAddress,Stateful,Protocol,LocalPort'
    'Remove-VMNetworkAdapterExtendedAcl' = '*InputObject'
    'Disconnect-VMNetworkAdapter'       = 'VMName'
    'Connect-VMNetworkAdapter'          = 'VMNetworkAdapter,SwitchName'
    'Get-VMDvdDrive'                    = 'VMName,VMSnapshot'
    'Get-VMHardDiskDrive'               = 'VMName,VMSnapshot'
    'Get-VMSnapshot'                    = 'VMName'
    'Checkpoint-VM'                     = 'Name,SnapshotName,~Passthru'
    'Remove-VMSnapshot'                 = 'VMSnapshot'
    'Start-VM'                          = 'Name'
    'Stop-VM'                           = 'Name,~TurnOff,~Force'
    'Get-VHD'                           = 'Path'
    'Get-NetFirewallRule'               = 'Name'
    'Get-NetFirewallAddressFilter'      = '*InputObject'
    'Get-NetFirewallInterfaceFilter'    = '*InputObject'
    'New-NetFirewallRule'               = 'Name,DisplayName,Description,Direction,Action,Profile,Protocol,Enabled,RemoteAddress,InterfaceAlias'
    'Remove-NetFirewallRule'            = 'Name'
    'Get-NetAdapterBinding'             = 'Name,ComponentID'
    'Get-LocalGroupMember'              = 'SID'
    'Get-LocalGroup'                    = 'SID'
    'Add-LocalGroupMember'              = 'SID,Member'
    'Remove-LocalGroupMember'           = 'SID,Member'
    'Get-CimInstance'                   = 'ClassName'
}

foreach ($name in $specs.Keys) {
    $decl = foreach ($p in $specs[$name].Split(',')) {
        if ($p.StartsWith('*')) { '[Parameter(ValueFromPipeline)]$' + $p.Substring(1) }
        elseif ($p.StartsWith('~')) { '[switch]$' + $p.Substring(1) }
        else { '$' + $p }
    }
    $body = '[CmdletBinding(SupportsShouldProcess)] param(' + ($decl -join ', ') + ') process { throw "stub ' + $name + ' called without a Mock" }'
    Set-Item -Path "function:$name" -Value ([scriptblock]::Create($body))
}

Export-ModuleMember -Function @($specs.Keys)
