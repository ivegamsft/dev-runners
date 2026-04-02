<#
.SYNOPSIS
  Checks Key Vault secrets for approaching expiry or staleness.

.DESCRIPTION
  Queries secrets in the Key Vault and reports those older than the threshold.
  Returns JSON with findings and exits non-zero if any secrets need rotation.

.PARAMETER KeyVaultName
  Name of the Key Vault to check.

.PARAMETER MaxAgeDays
  Maximum acceptable age in days before flagging for rotation (default: 90).

.PARAMETER SecretNames
  Names of secrets to check (default: admin-password, ado-pat).
#>
param(
  [Parameter(Mandatory)][string]$KeyVaultName,
  [int]$MaxAgeDays = 90,
  [string[]]$SecretNames = @('admin-password', 'ado-pat')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$findings = @()
$needsRotation = $false

foreach ($name in $SecretNames) {
  try {
    $secret = az keyvault secret show --vault-name $KeyVaultName --name $name -o json 2>$null | ConvertFrom-Json
    if (-not $secret) {
      $findings += @{ name = $name; status = 'MISSING'; message = 'Secret does not exist'; ageDays = -1 }
      $needsRotation = $true
      continue
    }

    $updated = [datetime]$secret.attributes.updated
    $ageDays = [math]::Floor(([datetime]::UtcNow - $updated).TotalDays)

    if ($ageDays -gt $MaxAgeDays) {
      $findings += @{ name = $name; status = 'STALE'; message = "Secret is $ageDays days old (max: $MaxAgeDays)"; ageDays = $ageDays }
      $needsRotation = $true
    } else {
      $findings += @{ name = $name; status = 'OK'; message = "Secret is $ageDays days old"; ageDays = $ageDays }
    }
  } catch {
    $findings += @{ name = $name; status = 'ERROR'; message = $_.Exception.Message; ageDays = -1 }
    $needsRotation = $true
  }
}

$report = @{
  keyVault = $KeyVaultName
  checkDate = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')
  maxAgeDays = $MaxAgeDays
  needsRotation = $needsRotation
  findings = $findings
} | ConvertTo-Json -Depth 4

Write-Host $report
if ($needsRotation) {
  Write-Host "`nWARNING: One or more secrets need attention." -ForegroundColor Yellow
  exit 1
}
Write-Host "`nAll secrets are within acceptable age." -ForegroundColor Green
