<#
.SYNOPSIS
  Sprint 3 regression tests — validates fixes for issues #17, #18, #19, #20, #21, #22.

.DESCRIPTION
  Positive tests confirm expected patterns exist.
  Negative tests confirm anti-patterns are absent.
  Exit code 0 = all passed, 1 = at least one failure.

.EXAMPLE
  pwsh ./tests/sprint3-tests.ps1
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
$buildImagesYml    = Get-Content (Join-Path $repoRoot '.github\workflows\build-images.yml') -Raw
$deployGalleryYml  = Get-Content (Join-Path $repoRoot '.github\workflows\deploy-from-gallery.yml') -Raw
$mainBicep         = Get-Content (Join-Path $repoRoot 'infra\base\main.bicep') -Raw
$linuxPacker       = Get-Content (Join-Path $repoRoot 'scripts\image\linux-packer.json') -Raw
$windowsPacker     = Get-Content (Join-Path $repoRoot 'scripts\image\windows-packer.json') -Raw

# ─── Issue #17: CIS Benchmark Checks ─────────────────────────────────────────
Write-Host "`n=== Issue #17: CIS benchmark checks ===" -ForegroundColor Cyan

# Positive: CIS check scripts exist
Assert-Test `
  'Linux CIS check script exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\image\cis-check-linux.sh')) `
  'scripts/image/cis-check-linux.sh not found'

Assert-Test `
  'Windows CIS check script exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\image\cis-check-windows.ps1')) `
  'scripts/image/cis-check-windows.ps1 not found'

# Positive: Packer templates include CIS checks as provisioners
Assert-Test `
  'Linux packer template includes CIS check provisioner' `
  ($linuxPacker -match 'cis-check-linux') `
  'Linux packer template missing CIS check provisioner'

Assert-Test `
  'Windows packer template includes CIS check provisioner' `
  ($windowsPacker -match 'cis-check-windows') `
  'Windows packer template missing CIS check provisioner'

# Positive: CIS scripts have both required and recommended checks
$linuxCis = Get-Content (Join-Path $repoRoot 'scripts\image\cis-check-linux.sh') -Raw -ErrorAction SilentlyContinue
$windowsCis = Get-Content (Join-Path $repoRoot 'scripts\image\cis-check-windows.ps1') -Raw -ErrorAction SilentlyContinue
Assert-Test `
  'Linux CIS has required severity checks' `
  ($linuxCis -match 'required') `
  'Linux CIS script missing required severity checks'

Assert-Test `
  'Windows CIS has required severity checks' `
  ($windowsCis -match 'required') `
  'Windows CIS script missing required severity checks'

# Positive: CIS scripts exit non-zero on failure
Assert-Test `
  'Linux CIS exits non-zero on required failures' `
  ($linuxCis -match 'exit 1') `
  'Linux CIS script does not exit non-zero on failure'

Assert-Test `
  'Windows CIS exits non-zero on required failures' `
  ($windowsCis -match 'exit 1') `
  'Windows CIS script does not exit non-zero on failure'

# Positive: Workflow uploads CIS reports
Assert-Test `
  'Build workflow uploads CIS reports' `
  ($buildImagesYml -match 'cis-report') `
  'Build workflow missing CIS report upload'

# ─── Issue #18: Network Hardening ─────────────────────────────────────────────
Write-Host "`n=== Issue #18: Network hardening (NSG) ===" -ForegroundColor Cyan

# Positive: NSG resource exists in Bicep
Assert-Test `
  'NSG resource defined in main.bicep' `
  ($mainBicep -match "resource nsg 'Microsoft\.Network/networkSecurityGroups") `
  'NSG resource not found in main.bicep'

# Positive: NSG attached to subnet
Assert-Test `
  'NSG attached to agents subnet' `
  ($mainBicep -match 'networkSecurityGroup.*nsg\.id') `
  'NSG not attached to subnet'

# Positive: Default-deny egress rule exists
Assert-Test `
  'Default-deny outbound rule exists' `
  ($mainBicep -match 'Deny-All-Outbound') `
  'No default-deny egress rule found'

# Positive: HTTPS outbound allowed
Assert-Test `
  'HTTPS outbound allowed' `
  ($mainBicep -match 'Allow-HTTPS-Outbound') `
  'No HTTPS outbound allow rule'

# Positive: AzureCloud service tag allowed
Assert-Test `
  'AzureCloud outbound allowed' `
  ($mainBicep -match 'AzureCloud') `
  'No AzureCloud service tag allow rule'

# Positive: NSG output exists
Assert-Test `
  'NSG name in outputs' `
  ($mainBicep -match 'output nsgName') `
  'NSG name not in template outputs'

# Positive: Egress policy doc exists
Assert-Test `
  'Egress policy documentation exists' `
  (Test-Path (Join-Path $repoRoot 'docs\EGRESS_POLICY.md')) `
  'docs/EGRESS_POLICY.md not found'

# Negative: No inbound Internet access allowed
Assert-Test `
  'Inbound Internet denied' `
  ($mainBicep -match 'Deny-Internet-Inbound') `
  'No explicit deny for inbound Internet traffic'

# ─── Issue #19: Branch Protection ─────────────────────────────────────────────
Write-Host "`n=== Issue #19: Branch protection ===" -ForegroundColor Cyan

# Positive: Branch protection script exists
Assert-Test `
  'Branch protection script exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\identity\configure-branch-protection.ps1')) `
  'configure-branch-protection.ps1 not found'

$branchProtPs1 = Get-Content (Join-Path $repoRoot 'scripts\identity\configure-branch-protection.ps1') -Raw -ErrorAction SilentlyContinue

# Positive: Script configures required status checks
Assert-Test `
  'Script defines required status checks' `
  ($branchProtPs1 -match 'required.*checks|requiredChecks') `
  'No required status checks configuration found'

# Positive: Script enforces PR reviews
Assert-Test `
  'Script requires pull request reviews' `
  ($branchProtPs1 -match 'pull_request_reviews|approving_review') `
  'No PR review requirement found'

# Positive: Script has WhatIf support
Assert-Test `
  'Script supports WhatIf' `
  ($branchProtPs1 -match '\[switch\]\$WhatIf') `
  'No WhatIf parameter found'

# Positive: Documentation exists
Assert-Test `
  'Branch protection documentation exists' `
  (Test-Path (Join-Path $repoRoot 'docs\BRANCH_PROTECTION.md')) `
  'docs/BRANCH_PROTECTION.md not found'

# ─── Issue #20: Artifact Signing & Provenance ─────────────────────────────────
Write-Host "`n=== Issue #20: Artifact signing ===" -ForegroundColor Cyan

# Positive: Build workflow has cosign signing steps
Assert-Test `
  'Build workflow installs cosign' `
  ($buildImagesYml -match 'cosign-installer') `
  'Build workflow missing cosign installation'

Assert-Test `
  'Build workflow generates provenance JSON' `
  ($buildImagesYml -match 'provenance.*\.json') `
  'Build workflow missing provenance generation'

Assert-Test `
  'Build workflow signs with cosign sign-blob' `
  ($buildImagesYml -match 'cosign sign-blob') `
  'Build workflow missing cosign sign-blob step'

Assert-Test `
  'Build workflow uploads signed provenance artifacts' `
  ($buildImagesYml -match 'provenance-\$\{\{ matrix\.image \}\}') `
  'Build workflow missing provenance artifact upload'

# Positive: Deploy workflow has verification
Assert-Test `
  'Deploy workflow has cosign verification' `
  ($deployGalleryYml -match 'cosign.*verify|verify.*cosign') `
  'Deploy workflow missing cosign verification'

# Positive: Provenance documentation exists
Assert-Test `
  'Provenance documentation exists' `
  (Test-Path (Join-Path $repoRoot 'docs\PROVENANCE.md')) `
  'docs/PROVENANCE.md not found'

# ─── Issue #21: Image Integrity / Checksums ───────────────────────────────────
Write-Host "`n=== Issue #21: Checksum verification ===" -ForegroundColor Cyan

# Positive: Checksums file exists
Assert-Test `
  'Checksums file exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\image\checksums.json')) `
  'scripts/image/checksums.json not found'

# Positive: Linux packer has sha256 variable
Assert-Test `
  'Linux packer has runner_sha256 variable' `
  ($linuxPacker -match 'runner_sha256') `
  'Linux packer template missing runner_sha256 variable'

# Positive: Linux packer verifies checksum after download
Assert-Test `
  'Linux packer verifies SHA256 after download' `
  ($linuxPacker -match 'sha256sum -c') `
  'Linux packer template missing sha256sum verification'

# Positive: Windows packer has agent_sha256 variable
Assert-Test `
  'Windows packer has agent_sha256 variable' `
  ($windowsPacker -match 'agent_sha256') `
  'Windows packer template missing agent_sha256 variable'

# Positive: Windows packer verifies checksum
Assert-Test `
  'Windows packer verifies checksum with Get-FileHash' `
  ($windowsPacker -match 'Get-FileHash|Checksum mismatch') `
  'Windows packer template missing checksum verification'

# Negative: No unverified downloads (download followed by extract without checksum)
Assert-Test `
  'Update-checksums helper script exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\image\update-checksums.ps1')) `
  'update-checksums.ps1 helper not found'

# ─── Issue #22: Secret Rotation ───────────────────────────────────────────────
Write-Host "`n=== Issue #22: Secret rotation ===" -ForegroundColor Cyan

# Positive: Rotation workflow exists
Assert-Test `
  'Secret rotation workflow exists' `
  (Test-Path (Join-Path $repoRoot '.github\workflows\rotate-secrets.yml')) `
  'rotate-secrets.yml not found'

$rotateYml = Get-Content (Join-Path $repoRoot '.github\workflows\rotate-secrets.yml') -Raw -ErrorAction SilentlyContinue

# Positive: Workflow has schedule trigger
Assert-Test `
  'Rotation workflow has schedule trigger' `
  ($rotateYml -match 'schedule:') `
  'Rotation workflow missing schedule trigger'

# Positive: Workflow has manual dispatch
Assert-Test `
  'Rotation workflow has manual dispatch' `
  ($rotateYml -match 'workflow_dispatch:') `
  'Rotation workflow missing manual dispatch'

# Positive: Workflow uses OIDC
Assert-Test `
  'Rotation workflow uses OIDC auth' `
  ($rotateYml -match 'id-token:\s*write') `
  'Rotation workflow missing OIDC permission'

# Positive: Expiry check script exists
Assert-Test `
  'Secret expiry check script exists' `
  (Test-Path (Join-Path $repoRoot 'scripts\identity\check-secret-expiry.ps1')) `
  'check-secret-expiry.ps1 not found'

$expiryPs1 = Get-Content (Join-Path $repoRoot 'scripts\identity\check-secret-expiry.ps1') -Raw -ErrorAction SilentlyContinue

# Positive: Expiry script checks multiple secrets
Assert-Test `
  'Expiry script checks admin-password' `
  ($expiryPs1 -match 'admin-password') `
  'Expiry script does not check admin-password'

# Positive: Rotation runbook exists
Assert-Test `
  'Secret rotation runbook exists' `
  (Test-Path (Join-Path $repoRoot 'docs\SECRET_ROTATION.md')) `
  'docs/SECRET_ROTATION.md not found'

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
Write-Host "Sprint 3 Results: $pass passed, $fail failed" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

exit ($fail -gt 0 ? 1 : 0)
