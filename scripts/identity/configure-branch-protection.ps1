<#
.SYNOPSIS
  Configures branch protection rules for the main branch using GitHub CLI.

.DESCRIPTION
  Requires: gh CLI authenticated with admin access to the repository.

.PARAMETER Owner
  Repository owner (org or user).

.PARAMETER Repo
  Repository name.

.PARAMETER Branch
  Branch to protect (default: main).

.PARAMETER WhatIf
  Preview changes without applying.
#>
param(
  [Parameter(Mandatory)][string]$Owner,
  [Parameter(Mandatory)][string]$Repo,
  [string]$Branch = 'main',
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Required status checks — must match workflow job names/check names
$requiredChecks = @(
  'analyze'                    # CodeQL (codeql.yml)
  'bicep-lint'                 # Security Infra (security-infra.yml)
  'powershell-lint'            # Security Infra (security-infra.yml)
  'verify-manifest'            # Manifest Guard (manifest-guard.yml)
  'actionlint'                 # Workflow Security (workflow-security.yml)
  'pin-check'                  # Workflow Security (workflow-security.yml)
  'sbom-and-scan'              # SBOM & Vuln Scan (sbom-vuln-scan.yml)
)

Write-Host "Configuring branch protection for $Owner/$Repo branch '$Branch'" -ForegroundColor Cyan

if ($WhatIf) {
  Write-Host "`n[WhatIf] Would apply the following rules:" -ForegroundColor Yellow
  Write-Host "  - Require pull request reviews (1 approval minimum)"
  Write-Host "  - Require branches to be up-to-date before merge"
  Write-Host "  - Required status checks:"
  foreach ($check in $requiredChecks) { Write-Host "    - $check" }
  Write-Host "  - Block force pushes"
  Write-Host "  - Block branch deletion"
  Write-Host "  - Enforce rules for administrators"
  exit 0
}

# Build the required_status_checks context array
$checksJson = ($requiredChecks | ForEach-Object { "{""context"":""$_""}" }) -join ','

# Use GitHub API to set branch protection
$body = @"
{
  "required_status_checks": {
    "strict": true,
    "contexts": [],
    "checks": [$checksJson]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": false
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": false
}
"@

Write-Host "Applying branch protection rules via GitHub API..." -ForegroundColor Cyan
$bodyFile = New-TemporaryFile
try {
  $body | Out-File $bodyFile -Encoding utf8
  gh api -X PUT "repos/$Owner/$Repo/branches/$Branch/protection" --input $bodyFile.FullName
  Write-Host "Branch protection configured successfully." -ForegroundColor Green
} finally {
  Remove-Item $bodyFile -Force -ErrorAction SilentlyContinue
}

# Display current protection
Write-Host "`nCurrent branch protection status:" -ForegroundColor Cyan
gh api "repos/$Owner/$Repo/branches/$Branch/protection" --jq '{
  required_reviews: .required_pull_request_reviews.required_approving_review_count,
  strict_status: .required_status_checks.strict,
  checks: [.required_status_checks.checks[].context],
  enforce_admins: .enforce_admins.enabled,
  allow_force_pushes: .allow_force_pushes.enabled,
  allow_deletions: .allow_deletions.enabled
}'
