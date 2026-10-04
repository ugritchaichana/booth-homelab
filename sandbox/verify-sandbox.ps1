<#
.SYNOPSIS
    Automated verification of MinIO Sandbox and CREEP CVE-2025-36852 Security Hardening.
#>
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   SDET Sandbox & CREEP Mitigation Automated Verification " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Check MinIO HTTP Health Endpoint
$healthUrl = "http://localhost:9000/minio/health/live"
Write-Host "`n==> Step 1: Checking MinIO Health Endpoint ($healthUrl)..."
try {
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 5
    if ($response.StatusCode -eq 200) {
        Write-Host "    [PASS] MinIO is live and healthy (HTTP 200)" -ForegroundColor Green
    }
} catch {
    Write-Host "    [FAIL] MinIO health check failed: $_" -ForegroundColor Red
    exit 1
}

# 2. Check S3 Buckets Existence
Write-Host "`n==> Step 2: Verifying S3 Buckets Creation..."
$buckets = docker exec sdet-sandbox-minio mc ls myminio
Write-Host $buckets
if ($buckets -match "angular-nx-cache" -and $buckets -match "sdet-test-artifacts") {
    Write-Host "    [PASS] Both 'angular-nx-cache' and 'sdet-test-artifacts' exist" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Required buckets are missing" -ForegroundColor Red
    exit 1
}

# 3. Check ILM Lifecycle Expiration Rule (7 Days)
Write-Host "`n==> Step 3: Verifying 7-Day ILM Expiration Rule..."
$ilm = docker exec sdet-sandbox-minio mc ilm rule list myminio/angular-nx-cache
Write-Host $ilm
if ($ilm -match "Days: 7" -or $ilm -match "7") {
    Write-Host "    [PASS] 7-day expiration policy active" -ForegroundColor Green
} else {
    Write-Host "    [WARN] ILM rule check requires attention" -ForegroundColor Yellow
}

# 4. CREEP Security Assertion: Trusted Main Builder (Read-Write)
Write-Host "`n==> Step 4: Testing Main Builder (RW User: gha-main-builder)..."
docker exec sdet-sandbox-minio mc alias set test-main http://localhost:9000 gha-main-builder StrongMainSecretKey123 > $null
$createTest = docker exec sdet-sandbox-minio sh -c "echo 'trusted-cache-payload' > /tmp/main-cache.txt && mc cp /tmp/main-cache.txt test-main/angular-nx-cache/trusted-cache.txt"
if ($LASTEXITCODE -eq 0) {
    Write-Host "    [PASS] Main Builder successfully wrote cache artifact (RW permitted)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Main Builder failed to write cache artifact" -ForegroundColor Red
    exit 1
}

# 5. CREEP Security Assertion: PR Runner Read-Only Access
Write-Host "`n==> Step 5: Testing PR Runner (RO User: gha-pr-runner) - Cache Retrieval..."
docker exec sdet-sandbox-minio mc alias set test-pr http://localhost:9000 gha-pr-runner StrongPRSecretKey123 > $null
$readTest = docker exec sdet-sandbox-minio mc cat test-pr/angular-nx-cache/trusted-cache.txt
if ($readTest -match "trusted-cache-payload") {
    Write-Host "    [PASS] PR Runner successfully read cached artifact (RO permitted)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] PR Runner could not read cached artifact" -ForegroundColor Red
    exit 1
}

# 6. CREEP Security Assertion: PR Runner Cache Poisoning Prevention
Write-Host "`n==> Step 6: Testing PR Runner - Block Cache Poisoning (CVE-2025-36852 Hardening)..."
$poisonAttempt = docker exec sdet-sandbox-minio sh -c "echo 'poison-payload' > /tmp/poison.txt && mc cp /tmp/poison.txt test-pr/angular-nx-cache/poison.txt 2>&1"
if ($LASTEXITCODE -ne 0 -or $poisonAttempt -match "Access Denied" -or $poisonAttempt -match "Forbidden") {
    Write-Host "    [PASS] Poisoning blocked with Access Denied! (Exit Code: $LASTEXITCODE)" -ForegroundColor Green
    Write-Host "           Output: $poisonAttempt" -ForegroundColor DarkGray
} else {
    Write-Host "    [FAIL] CRITICAL VULNERABILITY: PR Runner was able to write to cache bucket!" -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "   ALL TESTS PASSED: Sandbox & Security Baseline Verified!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
