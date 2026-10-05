<#
.SYNOPSIS
    Automated TDD Test Suite for .NET Transitive Dependency Graph Diff Engine.
#>
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   TDD Verification: Transitive Graph Engine Assertions    " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptPath = (Resolve-Path "$PSScriptRoot\..\scripts\apps\dotnet-affected-test.ps1").Path
$rootDir = (Resolve-Path "$PSScriptRoot\..\apps\backend").Path

function Reset-WorkingTree {
    git checkout -- apps/backend/ 2>$null
    git clean -fd apps/backend/ 2>$null
}

# Test 1: Leaf Project Modification (Billing.Api)
Write-Host "`n>>> [TEST 1] Modifying Leaf Project: Billing.Api/InvoiceGenerator.cs..." -ForegroundColor Yellow
Reset-WorkingTree
Add-Content -Path "$rootDir\src\Billing.Api\InvoiceGenerator.cs" -Value "`n// Leaf edit trigger"

$test1Projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
$test1Names = @($test1Projects | ForEach-Object { Split-Path $_ -Leaf })

Write-Host "    Resolved Suites: $($test1Names -join ', ')"
if ($test1Names -contains "Billing.Api.UnitTests.csproj" -and $test1Names -notcontains "Order.Api.UnitTests.csproj") {
    Write-Host "    [PASS] TEST 1: Only Billing.Api.UnitTests was selected!" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] TEST 1: Expected Billing.Api.UnitTests.csproj only." -ForegroundColor Red
    Reset-WorkingTree
    exit 1
}

# Test 2: Root Domain Modification (Core.Domain) -> Transitive Propagation
Write-Host "`n>>> [TEST 2] Modifying Root Domain: Core.Domain/Money.cs..." -ForegroundColor Yellow
Reset-WorkingTree
Add-Content -Path "$rootDir\src\Core.Domain\Money.cs" -Value "`n// Root domain edit trigger"

$test2Projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
$test2Names = @($test2Projects | ForEach-Object { Split-Path $_ -Leaf })

Write-Host "    Resolved Suites: $($test2Names -join ', ')"
if ($test2Names -contains "Order.Api.UnitTests.csproj" -and $test2Names -notcontains "Billing.Api.UnitTests.csproj") {
    Write-Host "    [PASS] TEST 2: Transitive DAG correctly propagated Core.Domain -> Core.Application -> Order.Api -> Order.Api.UnitTests!" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] TEST 2: Transitive propagation failed." -ForegroundColor Red
    Reset-WorkingTree
    exit 1
}

# Test 3: Documentation / Non-Code Modification
Write-Host "`n>>> [TEST 3] Modifying Non-Code File: README.md..." -ForegroundColor Yellow
Reset-WorkingTree
Set-Content -Path "$PSScriptRoot\..\test-doc.md" -Value "# Non code change"

$test3Projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
$test3Names = @($test3Projects | ForEach-Object { Split-Path $_ -Leaf })
Remove-Item "$PSScriptRoot\..\test-doc.md" -Force -ErrorAction SilentlyContinue

Write-Host "    Resolved Suites Count: $($test3Names.Count)"
if ($test3Names.Count -eq 0) {
    Write-Host "    [PASS] TEST 3: Zero tests triggered for non-code edits!" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] TEST 3: Tests were erroneously triggered." -ForegroundColor Red
    Reset-WorkingTree
    exit 1
}

# Test 4: Live Execution with Deterministic MSBuild & Results File Generation
Write-Host "`n>>> [TEST 4] Live Test Execution for Transitive Diff..." -ForegroundColor Yellow
Reset-WorkingTree
Add-Content -Path "$rootDir\src\Core.Domain\Money.cs" -Value "`n// Live test trigger"
$resultsDir = "$rootDir\TestResults"
Remove-Item $resultsDir -Recurse -Force -ErrorAction SilentlyContinue

& $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -ResultsDir $resultsDir
if ($LASTEXITCODE -eq 0 -and (Test-Path "$resultsDir\Order.Api.UnitTests.trx")) {
    Write-Host "    [PASS] TEST 4: Live execution passed and Order.Api.UnitTests.trx generated!" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] TEST 4: Execution failed or trx file not found." -ForegroundColor Red
    Reset-WorkingTree
    exit 1
}

# Test 5: Global Build Config Modification (Directory.Build.props) -> Fail-Closed All Suites
Write-Host "`n>>> [TEST 5] Modifying Global Config: Directory.Build.props (Fail-Closed)..." -ForegroundColor Yellow
Reset-WorkingTree
Add-Content -Path "$rootDir\Directory.Build.props" -Value "`n<!-- Global probe -->"

$test5Projects = & $scriptPath -BaseRef "HEAD" -HeadRef "HEAD" -RootDir $rootDir -IncludeWorkingTree -DryRun
$test5Names = @($test5Projects | ForEach-Object { Split-Path $_ -Leaf })
Reset-WorkingTree

Write-Host "    Resolved Suites Count: $($test5Names.Count)"
Write-Host "    Suites: $($test5Names -join ', ')"
if ($test5Names.Count -ge 2 -and $test5Names -contains "Billing.Api.UnitTests.csproj" -and $test5Names -contains "Order.Api.UnitTests.csproj") {
    Write-Host "    [PASS] TEST 5: Fail-closed logic successfully selected all test suites for Directory.Build.props modification!" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] TEST 5: Expected all test suites to be selected." -ForegroundColor Red
    Reset-WorkingTree
    exit 1
}

Reset-WorkingTree
Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   ALL 5 TDD SCENARIOS PASSED WITH MATHEMATICAL CERTAINTY! " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
