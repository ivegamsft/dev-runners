param(
  [string]$OutputPath = '..\..\manifests\agent-manifest.json'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RepoRoot {
  $gitRoot = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -eq 0 -and $gitRoot) {
    return $gitRoot.Trim()
  }

  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Get-RelativePath {
  param(
    [string]$BasePath,
    [string]$TargetPath
  )

  [System.IO.Path]::GetRelativePath($BasePath, $TargetPath).Replace('\', '/')
}

function Get-FileEntry {
  param(
    [string]$RepoRoot,
    [System.IO.FileInfo]$File
  )

  [pscustomobject]@{
    path = (Get-RelativePath -BasePath $RepoRoot -TargetPath $File.FullName)
    sizeBytes = $File.Length
    sha256 = (Get-FileHash -Path $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Get-InstallHintsFromTemplate {
  param(
    [string]$TemplatePath
  )

  $raw = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json
  $hints = New-Object System.Collections.Generic.List[string]

  if ($raw.provisioners) {
    foreach ($prov in $raw.provisioners) {
      if (-not (Get-Member -InputObject $prov -Name 'inline' -MemberType NoteProperty)) { continue }
      foreach ($line in $prov.inline) {
        if (
          $line -match 'apt-get install' -or
          $line -match 'choco install' -or
          $line -match 'Install-Module' -or
          $line -match 'installazd' -or
          $line -match 'setup_20\.x' -or
          $line -match 'python --version=' -or
          $line -match 'actions-runner-linux-x64-' -or
          $line -match 'vsts-agent-win-x64-'
        ) {
          $hints.Add($line)
        }
      }
    }
  }

  return @($hints)
}

$repoRoot = Get-RepoRoot
$resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  [System.IO.Path]::GetFullPath($OutputPath)
} else {
  [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $OutputPath))
}

$manifestDir = Split-Path -Parent $resolvedOutput
if (-not (Test-Path $manifestDir)) {
  New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}

$scriptFiles = @(Get-ChildItem (Join-Path $repoRoot 'scripts') -Recurse -File | Sort-Object FullName)
$agentFiles = @()
$agentDir = Join-Path $repoRoot '.github\agents'
if (Test-Path $agentDir) {
  $agentFiles = @(Get-ChildItem $agentDir -Filter *.agent.md -File | Sort-Object FullName)
}

$imageTemplates = @()
$templatePaths = @(
  (Join-Path $repoRoot 'scripts\image\linux-packer.json')
  (Join-Path $repoRoot 'scripts\image\windows-packer.json')
)

foreach ($template in $templatePaths) {
  if (-not (Test-Path $template)) { continue }

  $rawTemplate = Get-Content -Path $template -Raw | ConvertFrom-Json
  $variables = [ordered]@{}

  if ($rawTemplate.variables) {
    $rawTemplate.variables.PSObject.Properties | Sort-Object Name | ForEach-Object {
      $variables[$_.Name] = $_.Value
    }
  }

  $imageTemplates += [pscustomobject]@{
    path = (Get-RelativePath -BasePath $repoRoot -TargetPath $template)
    variables = [pscustomobject]$variables
    installHints = @(Get-InstallHintsFromTemplate -TemplatePath $template)
  }
}

$manifest = [ordered]@{
  schemaVersion = '1.0.0'
  description = 'Version-controlled inventory of scripts, Copilot custom agents, and runner image provisioning hints.'
  scripts = @($scriptFiles | ForEach-Object { Get-FileEntry -RepoRoot $repoRoot -File $_ })
  copilotAgents = @($agentFiles | ForEach-Object { Get-FileEntry -RepoRoot $repoRoot -File $_ })
  runnerImageTemplates = $imageTemplates
}

$json = $manifest | ConvertTo-Json -Depth 15
$json | Set-Content -Path $resolvedOutput -Encoding UTF8

Write-Host "Manifest updated: $resolvedOutput"
