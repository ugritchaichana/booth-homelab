[CmdletBinding()]
param(
    [string]$PesterVersion = '5.7.1',
    [string]$Filter,
    [string]$CoveragePath = (Join-Path ([IO.Path]::GetTempPath()) 'hyperv-coverage.xml'),
    [switch]$NoCoverage
)

$ErrorActionPreference = 'Stop'
Import-Module Pester -RequiredVersion $PesterVersion
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).ProviderPath
$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Normal'
if ($Filter) { $config.Filter.FullName = $Filter }
if (-not $NoCoverage) {
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = Join-Path $repo 'scripts\hyperv\HomelabHyperV.psm1'
    $config.CodeCoverage.CoveragePercentTarget = 0
    $config.CodeCoverage.OutputPath = $CoveragePath
}

$result = Invoke-Pester -Configuration $config
if (-not $NoCoverage) {
    $cc = $result.CodeCoverage
    Write-Host ('Coverage HomelabHyperV.psm1: {0:N2}% ({1} of {2} commands)' -f $cc.CoveragePercent, $cc.CommandsExecutedCount, $cc.CommandsAnalyzedCount)
    if ($env:GITHUB_STEP_SUMMARY) { Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ('Coverage HomelabHyperV.psm1: {0:N2}% ({1} of {2} commands)' -f $cc.CoveragePercent, $cc.CommandsExecutedCount, $cc.CommandsAnalyzedCount) }
    foreach ($m in $cc.CommandsMissed | Group-Object Line | Sort-Object { [int]$_.Name }) {
        Write-Host ('  missed line {0} ({1}): {2}' -f $m.Name, $m.Count, ($m.Group[0].Command -split "`r?`n")[0])
    }
}
if ($result.FailedCount -gt 0 -or $result.FailedBlocksCount -gt 0 -or $result.FailedContainersCount -gt 0) { exit 1 }
