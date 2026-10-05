<#
.SYNOPSIS
    Exact-set verification of the .NET transitive graph selector; every git write happens in a disposable clone.
#>
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptPath = if ($env:SELECTOR_PS1) { (Resolve-Path $env:SELECTOR_PS1).Path } else { (Resolve-Path (Join-Path (Join-Path (Join-Path $repoRoot "scripts") "apps") "dotnet-affected-test.ps1")).Path }

$billingUnit = "Billing.Api.UnitTests.csproj"
$orderUnit = "Order.Api.UnitTests.csproj"
$orderIntegration = "Order.Api.IntegrationTests.csproj"

$work = $null
$rootDir = $null
$pushed = $false
$exitCode = 0

function Invoke-Git {
    if (-not $work) { throw "Disposable clone path is not set; refusing to run git." }
    & git -C $work @args
    if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed with exit code $LASTEXITCODE" }
}

function Reset-Clone {
    Invoke-Git checkout --quiet .
    Invoke-Git clean -f -d -q
}

function Add-CloneLine([string]$RelativePath, [string]$Text) {
    Add-Content -LiteralPath (Join-Path $work $RelativePath) -Value $Text
}

function Assert-ExactSet([string]$Label, $Projects, [string[]]$Expected) {
    $actual = @(@($Projects) | Where-Object { $_ } | ForEach-Object { Split-Path $_ -Leaf } | Sort-Object)
    $want = @(@($Expected) | Where-Object { $_ } | Sort-Object)
    $actualText = if ($actual.Count) { $actual -join "," } else { "(none)" }
    $wantText = if ($want.Count) { $want -join "," } else { "(none)" }
    if ($actualText -ceq $wantText) {
        Write-Host "    [PASS] ${Label}: selected exactly {$actualText}" -ForegroundColor Green
    } else {
        Write-Host "    expected: {$wantText}" -ForegroundColor Red
        Write-Host "    actual:   {$actualText}" -ForegroundColor Red
        throw "${Label}: selected set differs from the ProjectReference-graph oracle"
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Verification: PowerShell Transitive Graph (exact sets)  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

try {
    $tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $work = Join-Path $tempBase ("selector-harness-" + [guid]::NewGuid().ToString("N").Substring(0, 8))

    & git clone --quiet --no-hardlinks $repoRoot $work
    if ($LASTEXITCODE -ne 0) { throw "git clone into $work failed with exit code $LASTEXITCODE" }

    Push-Location $work
    $pushed = $true
    $work = (Get-Location).Path
    $rootDir = [System.IO.Path]::GetFullPath((Join-Path (Join-Path $work "apps") "backend"))

    Write-Host "Source Repository: $repoRoot"
    Write-Host "Selector Script:   $scriptPath"
    Write-Host "Disposable Clone:  $work"

    if ($rootDir -match '(?i)test') {
        throw "Clone path contains 'test'; the selector's path-based test-project filter would match every project: $rootDir"
    }

    # Test 1: leaf project (Billing.Api)
    Write-Host "`n>>> [TEST 1] Modifying leaf project: Billing.Api/InvoiceGenerator.cs..." -ForegroundColor Yellow
    Reset-Clone
    Add-CloneLine "apps/backend/src/Billing.Api/InvoiceGenerator.cs" "// Leaf edit trigger"
    $projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
    Assert-ExactSet "TEST 1" $projects @($billingUnit, $orderIntegration)

    # Test 2: root domain (Core.Domain) with transitive propagation
    Write-Host "`n>>> [TEST 2] Modifying root domain: Core.Domain/Money.cs..." -ForegroundColor Yellow
    Reset-Clone
    Add-CloneLine "apps/backend/src/Core.Domain/Money.cs" "// Root domain edit trigger"
    $projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
    Assert-ExactSet "TEST 2" $projects @($orderUnit, $orderIntegration)

    # Test 3: documentation-only change
    Write-Host "`n>>> [TEST 3] Adding non-code file: test-doc.md..." -ForegroundColor Yellow
    Reset-Clone
    Set-Content -LiteralPath (Join-Path $work "test-doc.md") -Value "# Non code change"
    $projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
    Assert-ExactSet "TEST 3" $projects @()

    # Test 4: live execution with deterministic MSBuild and trx output
    Write-Host "`n>>> [TEST 4] Live test execution for transitive diff..." -ForegroundColor Yellow
    Reset-Clone
    Add-CloneLine "apps/backend/src/Core.Domain/Money.cs" "// Live test trigger"
    $resultsDir = Join-Path $rootDir "TestResults"
    & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -ResultsDir $resultsDir
    $missing = @($orderUnit, $orderIntegration | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) + ".trx" } | Where-Object { -not (Test-Path (Join-Path $resultsDir $_)) })
    if ($LASTEXITCODE -eq 0 -and $missing.Count -eq 0) {
        Write-Host "    [PASS] TEST 4: live execution passed and a trx was generated for Order.Api.UnitTests and Order.Api.IntegrationTests" -ForegroundColor Green
    } else {
        throw "TEST 4: execution failed (exit $LASTEXITCODE) or trx missing: $($missing -join ', ')"
    }

    # Test 5: shared build config, fail-closed
    Write-Host "`n>>> [TEST 5] Modifying shared config: Directory.Build.props (fail-closed)..." -ForegroundColor Yellow
    Reset-Clone
    Add-CloneLine "apps/backend/Directory.Build.props" "<!-- Global probe -->"
    $projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
    Assert-ExactSet "TEST 5" $projects @($billingUnit, $orderUnit, $orderIntegration)

    # Test 6: unmappable non-doc file, fail-closed
    Write-Host "`n>>> [TEST 6] Adding unmappable non-doc file: scripts/ci/probe.sh (fail-closed)..." -ForegroundColor Yellow
    Reset-Clone
    Set-Content -LiteralPath (Join-Path (Join-Path (Join-Path $work "scripts") "ci") "probe.sh") -Value "echo probe"
    $projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
    Assert-ExactSet "TEST 6" $projects @($billingUnit, $orderUnit, $orderIntegration)

    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "   ALL 6 SCENARIOS PASSED (EXACT SETS MATCH THE GRAPH)     " -ForegroundColor Green
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "    [FAIL] $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($pushed) { Pop-Location }
    if ($work -and ((Split-Path $work -Leaf) -like "selector-harness-*") -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
exit $exitCode
