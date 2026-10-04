<#
.SYNOPSIS
    Big Tech SaaS Transitive Dependency Graph Diff Test Runner for .NET
.DESCRIPTION
    Analyzes git diff against a base commit, maps changes to owning .csproj projects,
    recursively computes the full transitive dependency graph (DAG), and executes
    deterministic test suites only for downstream affected test projects.
#>
[CmdletBinding()]
param(
    [string]$BaseRef = "HEAD~1",
    [string]$HeadRef = "HEAD",
    [string]$RootDir,
    [string]$ResultsDir,
    [switch]$IncludeWorkingTree,
    [switch]$DryRun,
    [switch]$Deterministic = $true
)

$ErrorActionPreference = "Stop"

if (-not $RootDir) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $RootDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\..\sdet\backend"))
}
if (-not $ResultsDir) {
    $ResultsDir = [System.IO.Path]::GetFullPath((Join-Path $RootDir "TestResults"))
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   .NET Transitive Dependency Graph Affected Test Runner   " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Root Directory:    $RootDir"
Write-Host "Base Reference:    $BaseRef"
Write-Host "Head Reference:    $HeadRef"
Write-Host "Include Working:   $IncludeWorkingTree"

# 1. Collect Changed Files
$changedFiles = [System.Collections.Generic.List[string]]::new()
$gitWarningPref = $env:GIT_REDIRECT_STDERR
$env:GIT_REDIRECT_STDERR = '2>&1'

try {
    $diff = git diff --name-only "$BaseRef" "$HeadRef" 2>$null
    if ($LASTEXITCODE -eq 0 -and $diff) {
        foreach ($line in ($diff -split "`r?`n")) {
            if ($line.Trim()) { $changedFiles.Add($line.Trim()) }
        }
    }
} catch {
    Write-Host "    [Notice] No commit range found. Checking working tree..." -ForegroundColor DarkGray
}

if ($IncludeWorkingTree) {
    $uncommitted = git diff --name-only 2>$null
    if ($uncommitted) {
        foreach ($line in ($uncommitted -split "`r?`n")) {
            if ($line.Trim() -and -not $line.StartsWith("warning:")) { $changedFiles.Add($line.Trim()) }
        }
    }
    $untracked = git status --porcelain 2>$null
    if ($untracked) {
        foreach ($line in ($untracked -split "`r?`n")) {
            if ($line -match '^\?\?\s+(.*)') {
                $changedFiles.Add($Matches[1].Trim())
            }
        }
    }
}

$uniqueChanged = @($changedFiles | Select-Object -Unique)
Write-Host "`n==> Step 1: Changed Files Detected ($($uniqueChanged.Count)):"
$uniqueChanged | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }

if ($uniqueChanged.Count -eq 0) {
    Write-Host "`n[OK] No changes detected. Zero tests required." -ForegroundColor Green
    if ($DryRun) { return @() }
    exit 0
}

# 2. Map Changed Files to Owning .csproj Projects
$allCsprojFiles = Get-ChildItem -Path $RootDir -Filter "*.csproj" -Recurse | Select-Object -ExpandProperty FullName
$directProjects = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($file in $uniqueChanged) {
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $file))
    
    if (-not $fullPath.StartsWith($RootDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $currentDir = Split-Path -Path $fullPath -Parent
    while ($currentDir -and $currentDir.Length -ge $RootDir.Length) {
        $csproj = Get-ChildItem -Path $currentDir -Filter "*.csproj" -File | Select-Object -First 1
        if ($csproj) {
            $directProjects.Add($csproj.FullName) | Out-Null
            break
        }
        $parent = Split-Path -Path $currentDir -Parent
        if ($parent -eq $currentDir) { break }
        $currentDir = $parent
    }
}

Write-Host "`n==> Step 2: Directly Modified Projects ($($directProjects.Count)):"
$directProjects | ForEach-Object { Write-Host "    - $(Split-Path $_ -Leaf)" -ForegroundColor Yellow }

if ($directProjects.Count -eq 0) {
    Write-Host "`n[OK] Modified files do not belong to any .NET project. Skipping test execution." -ForegroundColor Green
    if ($DryRun) { return @() }
    exit 0
}

# 3. Build Reverse Dependency Graph (Child -> Parents / Dependents)
$reverseGraph = @{}
foreach ($csproj in $allCsprojFiles) {
    $normPath = [System.IO.Path]::GetFullPath($csproj)
    if (-not $reverseGraph.ContainsKey($normPath)) {
        $reverseGraph[$normPath] = [System.Collections.Generic.List[string]]::new()
    }
}

foreach ($csproj in $allCsprojFiles) {
    $parentPath = [System.IO.Path]::GetFullPath($csproj)
    $dir = Split-Path $parentPath -Parent
    
    [xml]$xml = Get-Content $parentPath
    $projRefs = $xml.SelectNodes("//ProjectReference/@Include")
    if ($projRefs) {
        foreach ($ref in $projRefs) {
            $relPath = $ref.Value -replace '\\', [System.IO.Path]::DirectorySeparatorChar -replace '/', [System.IO.Path]::DirectorySeparatorChar
            $childPath = [System.IO.Path]::GetFullPath((Join-Path $dir $relPath))
            
            if ($reverseGraph.ContainsKey($childPath)) {
                $reverseGraph[$childPath].Add($parentPath)
            }
        }
    }
}

# 4. Transitive Graph Traversal (BFS)
$affectedAll = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$queue = [System.Collections.Generic.Queue[string]]::new()

foreach ($dp in $directProjects) {
    $norm = [System.IO.Path]::GetFullPath($dp)
    $affectedAll.Add($norm) | Out-Null
    $queue.Enqueue($norm)
}

while ($queue.Count -gt 0) {
    $curr = $queue.Dequeue()
    if ($reverseGraph.ContainsKey($curr)) {
        foreach ($dep in $reverseGraph[$curr]) {
            if ($affectedAll.Add($dep)) {
                $queue.Enqueue($dep)
            }
        }
    }
}

# 5. Filter Down to Affected Test Projects
$affectedTestProjects = [System.Collections.Generic.List[string]]::new()
foreach ($item in $affectedAll) {
    $isTest = $false
    $leaf = Split-Path $item -Leaf
    if ($leaf -match "Test") {
        $isTest = $true
    } else {
        $content = Get-Content $item -Raw
        if ($content -match "Microsoft\.NET\.Test\.Sdk") {
            $isTest = $true
        }
    }
    
    if ($isTest) {
        $affectedTestProjects.Add($item)
    }
}

Write-Host "`n==> Step 3: Transitive Downstream Resolution:"
Write-Host "    Total Transitive Projects Affected: $($affectedAll.Count)"
Write-Host "    Target Test Suites to Execute:       $($affectedTestProjects.Count)"
$affectedTestProjects | ForEach-Object { Write-Host "    ==> [RUN] $(Split-Path $_ -Leaf)" -ForegroundColor Cyan }

if ($DryRun) {
    Write-Host "`n[DryRun] Returning affected suites." -ForegroundColor Magenta
    return ,$affectedTestProjects.ToArray()
}

if ($affectedTestProjects.Count -eq 0) {
    Write-Host "`n[OK] No test projects affected by this changeset. Skipping." -ForegroundColor Green
    exit 0
}

# 6. Execute Deterministic Tests
if (-not (Test-Path $ResultsDir)) {
    New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
}

$failed = $false
foreach ($testProj in $affectedTestProjects) {
    $projName = [System.IO.Path]::GetFileNameWithoutExtension($testProj)
    Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "  Executing Suite: $projName" -ForegroundColor DarkCyan
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkCyan
    
    $runArgs = @(
        "test",
        $testProj,
        "--no-restore",
        "--configuration", "Release",
        "--logger", "trx;LogFileName=$projName.trx",
        "--logger", "console;verbosity=normal",
        "--results-directory", $ResultsDir
    )
    if ($Deterministic) {
        $runArgs += "/p:Deterministic=true"
    }

    & dotnet @runArgs
    if ($LASTEXITCODE -ne 0) {
        $failed = $true
        Write-Host "    [FAIL] Test suite failed: $projName" -ForegroundColor Red
    } else {
        Write-Host "    [PASS] Test suite passed: $projName" -ForegroundColor Green
    }
}

if ($failed) {
    Write-Host "`n[ERROR] One or more affected test suites failed." -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   ALL AFFECTED SUITES PASSED DETERMINISTICALLY!           " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
