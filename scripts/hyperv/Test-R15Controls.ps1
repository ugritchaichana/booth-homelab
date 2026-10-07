[CmdletBinding()]
param(
    [string]$TargetsFile = (Join-Path $PSScriptRoot '..\..\tests\isolation\targets.env'),
    [ValidateRange(200, 30000)][int]$TimeoutMs = 3000
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not (Test-Path -LiteralPath $TargetsFile -PathType Leaf)) {
    throw "No targets file at $TargetsFile. Copy tests/isolation/targets.example.env to targets.env first."
}

function Test-TcpConnect {
    param([string]$Address, [int]$Port, [int]$TimeoutMs)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($pending)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

foreach ($line in Get-Content -LiteralPath $TargetsFile) {
    $text = $line.Trim()
    if ($text -eq '' -or $text.StartsWith('#')) { continue }
    $label, $rest = $text -split '=', 2
    $field = @($rest -split '\s+')
    if ($label -notmatch '^[a-z0-9_]+$' -or $field.Count -ne 7) { throw "Malformed row: $label" }
    $kind = $field[1]
    $address = $field[2]
    $port = [int]$field[3]
    $target = '{0}:{1}' -f $address, $port
    if ($kind -notin @('tcp', 'tcp6', 'tcpvia')) { throw "$label : kind must be tcp, tcp6 or tcpvia" }
    if ($port -lt 1 -or $port -gt 65535) { throw "$label : invalid port" }
    if ($address.Contains('%')) {
        Write-Output ('CONTROL {0} {1} n/a' -f $label, $target)
        continue
    }
    $reached = Test-TcpConnect -Address $address -Port $port -TimeoutMs $TimeoutMs
    Write-Output ('CONTROL {0} {1} {2}' -f $label, $target, $reached)
}
