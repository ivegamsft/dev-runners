<#
.SYNOPSIS
  Sprint 1 regression tests — validates fixes for issues #5, #6, #7, #8, #9, #10.

.DESCRIPTION
  Positive tests confirm expected patterns exist.
  Negative tests confirm anti-patterns are absent.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/sprint1-tests.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSScriptRoot -Parent
$pass = 0
$fail = 0

function Assert-Test {
  param([string]$Name, [bool]$Condition, [string]$FailMessage)
  if ($Condition) {
    Write-Host "  PASS: $Name" -ForegroundColor Green
    $script:pass++
  } else {
    Write-Host "  FAIL: $Name — $FailMessage" -ForegroundColor Red
    $script:fail++
  }
}

# ─── Load file contents ──────────────────────────────────────────────────────
$buildImagesYml   = Get-Content (Join-Path $repoRoot '.github\workflows\build-images.yml') -Raw
$deployGalleryYml = Get-Content (Join-Path $repoRoot '.github\workflows\deploy-from-gallery.yml') -Raw
$deployGalleryPs1 = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-from-gallery.ps1') -Raw
$deployImagesPs1  = Get-Content (Join-Path $repoRoot 'scripts\deploy\deploy-images.ps1') -Raw

# ─── Issue #5: Azure Login must exist in build job ───────────────────────────
Write-Host "`n=== Issue #5: Azure Login in build job ===" -ForegroundColor Cyan

# Positive: build job has azure/login step
$buildJobSection = ($buildImagesYml -split '(?m)^\s+build:')[1]
$buildJobSection = if ($buildJobSection) { ($buildJobSection -split '(?m)^\s+summary:')[0] } else { '' }
Assert-Test `
  'Build job contains azure/login step' `
  ($buildJobSection -match 'azure/login@v') `
  'azure/login action not found in build job'

# Positive: build job has OIDC secret references
Assert-Test `
  'Build job azure login uses OIDC secrets' `
  ($buildJobSection -match 'secrets\.AZURE_CLIENT_ID' -and $buildJobSection -match 'secrets\.AZURE_TENANT_ID') `
  'OIDC secret references missing from build job login step'

# Negative: summary job should also have login (pre-existing)
$summarySection = ($buildImagesYml -split '(?m)^\s+summary:')[1]
Assert-Test `
  'Summary job also has azure/login' `
  ($summarySection -and $summarySection -match 'azure/login@v') `
  'Summary job missing azure/login step'

# ─── Issue #6: No invalid env context in build job env block ─────────────────
Write-Host "`n=== Issue #6: No invalid env context remapping ===" -ForegroundColor Cyan

# Negative: job-level env must NOT use ${{ env.* }} (invalid in that context)
$buildEnvBlock = if ($buildJobSection -match '(?s)env:\s*\n((?:\s+\S.*\n)*)') { $Matches[1] } else { '' }
Assert-Test `
  'Build job env block does not use ${{ env.* }}' `
  (-not ($buildEnvBlock -match '\$\{\{\s*env\.')) `
  'Found ${{ env.* }} reference in build job env block — invalid context'

# Positive: build job env block has explicit literal values
Assert-Test `
  'Build job env has PACKER_LOCATION as literal' `
  ($buildEnvBlock -match 'PACKER_LOCATION:\s*\S') `
  'PACKER_LOCATION not found or empty in build job env'

Assert-Test `
  'Build job env has GALLERY_NAME as literal' `
  ($buildEnvBlock -match 'GALLERY_NAME:\s*\S') `
  'GALLERY_NAME not found in build job env'

# ─── Issue #7: No printing of params with adminPassword ─────────────────────
Write-Host "`n=== Issue #7: No printing secret-bearing params ===" -ForegroundColor Cyan

# Negative: deploy-from-gallery workflow must NOT cat the params file
Assert-Test `
  'deploy-from-gallery.yml does not cat deploy-params.json' `
  (-not ($deployGalleryYml -match 'cat\s+deploy-params\.json')) `
  'Found cat deploy-params.json — would print admin password to logs'

# Negative: no command that reads/displays the params file (cat > is write, not read)
$printPatterns = [regex]::Matches($deployGalleryYml, '(?im)^\s*(cat|more|type|less)\s+deploy-params\.json')
Assert-Test `
  'No debug print of params file content in workflow' `
  ($printPatterns.Count -eq 0) `
  'Found a command that prints the parameters file'

# Positive: adminPassword is sourced from a step output, not raw secret
Assert-Test `
  'adminPassword comes from step output (masked)' `
  ($deployGalleryYml -match 'steps\.admin_password\.outputs\.value') `
  'adminPassword not using step output with masking'

# ─── Issue #8: Template path uses PSScriptRoot ───────────────────────────────
Write-Host "`n=== Issue #8: Template path via PSScriptRoot ===" -ForegroundColor Cyan

# Positive: deploy-from-gallery.ps1 resolves template via $PSScriptRoot
Assert-Test `
  'deploy-from-gallery.ps1 uses $PSScriptRoot for template path' `
  ($deployGalleryPs1 -match '\$PSScriptRoot.*infra.*deploy.*main\.bicep') `
  'Template path not resolved via $PSScriptRoot'

# Negative: must NOT use bare relative path in az command
Assert-Test `
  'No bare relative "infra/deploy/main.bicep" in az command' `
  (-not ($deployGalleryPs1 -match 'az\s+deployment.*-f\s+"infra/')) `
  'Found bare relative path in az deployment command'

# Positive: template file existence is checked
Assert-Test `
  'Template file existence is validated before use' `
  ($deployGalleryPs1 -match 'Test-Path\s+\$TemplateFile') `
  'No Test-Path check for template file'

# ─── Issue #9: No unused Location parameter in deploy-images.ps1 ────────────
Write-Host "`n=== Issue #9: No unused parameters ===" -ForegroundColor Cyan

# Negative: deploy-images.ps1 must NOT declare $Location that is unused
$hasLocationParam = $deployImagesPs1 -match '(?m)^\s*\[string\]\$Location'
$usesLocation = ($deployImagesPs1 -replace '(?m)^\s*\[string\]\$Location.*$','') -match '\$Location'
Assert-Test `
  'deploy-images.ps1 does not have unused Location param' `
  (-not ($hasLocationParam -and -not $usesLocation)) `
  'Location parameter is declared but never used'

# Positive: all declared params in deploy-images.ps1 are used
$paramBlock = if ($deployImagesPs1 -match '(?s)param\s*\((.*?)\)') { $Matches[1] } else { '' }
$declaredParams = [regex]::Matches($paramBlock, '\$(\w+)') | ForEach-Object { $_.Groups[1].Value }
$bodyAfterParam = ($deployImagesPs1 -split '(?s)param\s*\(.*?\)')[1]
$unusedParams = @()
foreach ($p in $declaredParams) {
  if ($p -eq 'WhatIf') { continue }  # switch params used via .IsPresent
  if ($bodyAfterParam -notmatch [regex]::Escape("`$$p")) { $unusedParams += $p }
}
Assert-Test `
  'All declared parameters in deploy-images.ps1 are used in body' `
  ($unusedParams.Count -eq 0) `
  "Unused parameters: $($unusedParams -join ', ')"

# ─── Issue #10: Temp file cleanup in deploy-from-gallery.ps1 ────────────────
Write-Host "`n=== Issue #10: Secure temp file cleanup ===" -ForegroundColor Cyan

# Positive: try/finally block exists
Assert-Test `
  'deploy-from-gallery.ps1 has try/finally pattern' `
  ($deployGalleryPs1 -match '(?s)try\s*\{.*finally\s*\{') `
  'No try/finally block found'

# Positive: temp file is deleted in finally
Assert-Test `
  'Temp parameter file is removed in finally block' `
  ($deployGalleryPs1 -match 'Remove-Item.*tempParamFile') `
  'No Remove-Item for temp param file'

# Positive: plaintext password variable is cleared
Assert-Test `
  'Plaintext password variable is cleared after use' `
  ($deployGalleryPs1 -match '\$plainPw\s*=\s*\$null') `
  'Plaintext password variable not cleared'

# Negative: no plaintext password assignment outside try/finally (the $null clear inside finally is OK)
$lines = $deployGalleryPs1 -split "`n"
$inFinally = $false
$afterFinally = $false
$pwAfterFinally = $false
foreach ($line in $lines) {
  if ($line -match '^\s*finally\s*\{') { $inFinally = $true; continue }
  if ($inFinally -and $line -match '^\}') { $afterFinally = $true; $inFinally = $false; continue }
  if ($afterFinally -and $line -match '\$plainPw') { $pwAfterFinally = $true }
}
Assert-Test `
  'No plaintext password usage after finally block' `
  (-not $pwAfterFinally) `
  'Found $plainPw reference after finally block'

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Sprint 1 Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
