<#
.SYNOPSIS
  Downloads runner/agent binaries and computes their SHA256 checksums.
  Updates scripts/image/checksums.json with fresh values.

.DESCRIPTION
  Run this script after bumping version numbers in the packer templates.
  It downloads each binary, computes SHA256, and updates the checksums file.
#>
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$checksumFile = Join-Path $PSScriptRoot 'checksums.json'

# Read current packer templates for versions
$linuxTemplate = Get-Content (Join-Path $PSScriptRoot 'linux-packer.json') -Raw | ConvertFrom-Json
$windowsTemplate = Get-Content (Join-Path $PSScriptRoot 'windows-packer.json') -Raw | ConvertFrom-Json

$runnerVersion = $linuxTemplate.variables.runner_version
$agentVersion = $windowsTemplate.variables.agent_version

Write-Host "Runner version: $runnerVersion" -ForegroundColor Cyan
Write-Host "Agent version: $agentVersion" -ForegroundColor Cyan

$binaries = @(
  @{
    name = "actions-runner-linux-x64-$runnerVersion.tar.gz"
    url = "https://github.com/actions/runner/releases/download/v$runnerVersion/actions-runner-linux-x64-$runnerVersion.tar.gz"
    version = $runnerVersion
  },
  @{
    name = "vsts-agent-win-x64-$agentVersion.zip"
    url = "https://vstsagentpackage.azureedge.net/agent/$agentVersion/vsts-agent-win-x64-$agentVersion.zip"
    version = $agentVersion
  }
)

$checksumData = @{ description = "Pinned checksums for runner/agent binaries. Update when changing versions."; binaries = @{}; _update_instructions = "Run: pwsh scripts/image/update-checksums.ps1 to refresh checksums after version bumps." }

foreach ($bin in $binaries) {
  $tempFile = Join-Path $env:TEMP $bin.name
  Write-Host "Downloading $($bin.name)..." -ForegroundColor Yellow

  if ($DryRun) {
    Write-Host "  [DryRun] Would download from $($bin.url)"
    $sha = 'PLACEHOLDER_DRY_RUN'
  } else {
    Invoke-WebRequest -Uri $bin.url -OutFile $tempFile -UseBasicParsing
    $sha = (Get-FileHash $tempFile -Algorithm SHA256).Hash.ToLower()
    Remove-Item $tempFile -Force
  }

  Write-Host "  SHA256: $sha" -ForegroundColor Green
  $checksumData.binaries[$bin.name] = @{ url = $bin.url; sha256 = $sha; version = $bin.version }
}

$checksumData | ConvertTo-Json -Depth 4 | Out-File $checksumFile -Encoding utf8
Write-Host "`nChecksums written to $checksumFile" -ForegroundColor Green
