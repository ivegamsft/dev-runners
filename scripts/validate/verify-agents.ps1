<#
.SYNOPSIS
  Verify that deployed build agents register and come online.

.DESCRIPTION
  Post-deploy smoke test that checks:
  - Linux VMSS instances register as Azure DevOps agents in the specified pool
  - Windows VM registers as a GitHub Actions self-hosted runner
  - Both agents report an online/idle status
  Requires: az CLI (logged in), gh CLI (authenticated).

.PARAMETER SubscriptionId
  Azure subscription ID.

.PARAMETER ResourceGroup
  Azure resource group containing the deployed agents.

.PARAMETER AdoOrgUrl
  Azure DevOps organization URL (e.g. https://dev.azure.com/myorg).

.PARAMETER AdoPoolName
  Azure DevOps agent pool name. Default: 'Default'.

.PARAMETER GitHubRepo
  GitHub repository in owner/repo format (e.g. myorg/dev-runners).

.PARAMETER TimeoutSeconds
  Max seconds to wait for agents to come online. Default: 300 (5 minutes).

.PARAMETER EnvConfig
  Path to env config JSON. Defaults to env/dev.json.

.EXAMPLE
  pwsh scripts/validate/verify-agents.ps1 `
    -SubscriptionId 00000000-... `
    -ResourceGroup rg-myorg-dev-eus2 `
    -AdoOrgUrl https://dev.azure.com/myorg `
    -GitHubRepo myorg/dev-runners

.EXAMPLE
  # Auto-load from env/dev.json
  pwsh scripts/validate/verify-agents.ps1 -SubscriptionId 00000000-...
#>
param(
  [Parameter(Mandatory)]
  [string]$SubscriptionId,

  [string]$ResourceGroup,
  [string]$AdoOrgUrl,
  [string]$AdoPoolName,
  [string]$GitHubRepo,
  [int]$TimeoutSeconds = 300,
  [string]$EnvConfig
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Load config defaults ─────────────────────────────────────────────────────
if (-not $EnvConfig) {
  $EnvConfig = Join-Path $PSScriptRoot '..\..\env\dev.json'
}
if (Test-Path $EnvConfig) {
  $cfg = Get-Content $EnvConfig -Raw | ConvertFrom-Json
  if (-not $ResourceGroup)  { $ResourceGroup  = $cfg.RESOURCE_GROUP }
  if (-not $AdoOrgUrl)      { $AdoOrgUrl      = $cfg.ADO_ORG_URL }
  if (-not $AdoPoolName)    { $AdoPoolName    = $cfg.ADO_POOL_NAME }
  if (-not $GitHubRepo)     { $GitHubRepo     = $cfg.GITHUB_REPO }
}

if (-not $ResourceGroup) {
  Write-Error 'ResourceGroup is required. Provide -ResourceGroup or set RESOURCE_GROUP in env config.'
  exit 1
}

if (-not $AdoPoolName) { $AdoPoolName = 'Default' }

$pass = 0
$fail = 0

function Write-Section($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Assert-Check {
  param([string]$Name, [bool]$Condition, [string]$FailMessage)
  if ($Condition) {
    Write-Host "  PASS: $Name" -ForegroundColor Green
    $script:pass++
  } else {
    Write-Host "  FAIL: $Name — $FailMessage" -ForegroundColor Red
    $script:fail++
  }
}

az account set --subscription $SubscriptionId 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to set subscription $SubscriptionId"
  exit 1
}

# ─── Discover deployed resources ──────────────────────────────────────────────
Write-Section 'Discovering deployed compute resources'

$vmss = az vmss list -g $ResourceGroup --query '[0]' -o json 2>$null | ConvertFrom-Json
$ghVm = az vm list -g $ResourceGroup -o json 2>$null | ConvertFrom-Json | Where-Object { $_.name -match '-gh-' } | Select-Object -First 1

Assert-Check 'Linux VMSS found in resource group' ($null -ne $vmss) "No VMSS in $ResourceGroup"
Assert-Check 'GitHub runner VM found in resource group' ($null -ne $ghVm) "No VM matching '-gh-' in $ResourceGroup"

if ($vmss) {
  $vmssName = $vmss.name
  $instanceCount = (az vmss list-instances -g $ResourceGroup --name $vmssName --query 'length(@)' -o tsv 2>$null)
  Assert-Check "VMSS '$vmssName' has running instances" ([int]$instanceCount -gt 0) "VMSS has 0 instances — scale up first"
  Write-Host "    VMSS: $vmssName ($instanceCount instance(s))" -ForegroundColor Gray
}

if ($ghVm) {
  $vmName = $ghVm.name
  $vmStatus = az vm get-instance-view -g $ResourceGroup --name $vmName --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>$null
  Assert-Check "GitHub runner VM '$vmName' is running" ($vmStatus -eq 'VM running') "VM status: $vmStatus"
  Write-Host "    VM: $vmName ($vmStatus)" -ForegroundColor Gray
}

# ─── Azure DevOps Agent Pool Check ───────────────────────────────────────────
Write-Section 'Azure DevOps agent registration'

if (-not $AdoOrgUrl) {
  Write-Host '  SKIP: ADO_ORG_URL not provided — skipping ADO agent checks' -ForegroundColor Yellow
} else {
  # Get a PAT or use az devops login token
  $adoToken = $null
  try {
    $adoToken = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv 2>$null
  } catch { }

  if (-not $adoToken) {
    Write-Host '  SKIP: Could not obtain Azure DevOps access token — ensure az CLI is logged in with an identity that has ADO access' -ForegroundColor Yellow
  } else {
    $headers = @{ Authorization = "Bearer $adoToken"; 'Content-Type' = 'application/json' }
    $orgName = ($AdoOrgUrl -replace 'https://dev.azure.com/', '' -replace '/$', '')

    # List pools to find the target
    try {
      $poolsResponse = Invoke-RestMethod -Uri "$AdoOrgUrl/_apis/distributedtask/pools?api-version=7.1" -Headers $headers -Method Get
      $targetPool = $poolsResponse.value | Where-Object { $_.name -eq $AdoPoolName } | Select-Object -First 1

      Assert-Check "ADO pool '$AdoPoolName' exists in org '$orgName'" ($null -ne $targetPool) "Pool '$AdoPoolName' not found"

      if ($targetPool) {
        $poolId = $targetPool.id

        # Poll for agents with timeout
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $onlineAgents = @()
        $allAgents = @()
        $pollInterval = 15

        Write-Host "    Waiting for ADO agents (pool $AdoPoolName, timeout ${TimeoutSeconds}s)..." -ForegroundColor Gray

        do {
          $agentsResponse = Invoke-RestMethod -Uri "$AdoOrgUrl/_apis/distributedtask/pools/$poolId/agents?includeCapabilities=true&api-version=7.1" -Headers $headers -Method Get
          $allAgents = $agentsResponse.value
          $onlineAgents = $allAgents | Where-Object { $_.status -eq 'online' }

          if ($onlineAgents.Count -gt 0) { break }

          if ((Get-Date) -lt $deadline) {
            Write-Host "    No online agents yet, retrying in ${pollInterval}s..." -ForegroundColor Gray
            Start-Sleep -Seconds $pollInterval
          }
        } while ((Get-Date) -lt $deadline)

        Assert-Check "ADO agents registered in pool '$AdoPoolName'" ($allAgents.Count -gt 0) 'No agents found in pool'
        Assert-Check 'At least one ADO agent is online' ($onlineAgents.Count -gt 0) "Found $($allAgents.Count) agent(s) but none online"

        foreach ($agent in $onlineAgents) {
          Write-Host "    Agent: $($agent.name) — status: $($agent.status), version: $($agent.version)" -ForegroundColor Gray
          $caps = $agent.systemCapabilities
          if ($caps) {
            $os = if ($caps.'Agent.OS') { $caps.'Agent.OS' } else { 'unknown' }
            $hostname = if ($caps.'Agent.ComputerName') { $caps.'Agent.ComputerName' } else { 'unknown' }
            Write-Host "      OS: $os, Hostname: $hostname" -ForegroundColor Gray
          }
        }
      }
    } catch {
      Assert-Check 'ADO API reachable' $false $_.Exception.Message
    }
  }
}

# ─── GitHub Actions Runner Check ──────────────────────────────────────────────
Write-Section 'GitHub Actions runner registration'

if (-not $GitHubRepo) {
  Write-Host '  SKIP: GITHUB_REPO not provided — skipping GitHub runner checks' -ForegroundColor Yellow
} else {
  try {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $onlineRunners = @()
    $allRunners = @()
    $pollInterval = 15

    Write-Host "    Waiting for GitHub runners ($GitHubRepo, timeout ${TimeoutSeconds}s)..." -ForegroundColor Gray

    do {
      $runnersJson = gh api "repos/$GitHubRepo/actions/runners" --jq '.runners' 2>$null
      if ($LASTEXITCODE -eq 0 -and $runnersJson) {
        $allRunners = $runnersJson | ConvertFrom-Json
        $onlineRunners = $allRunners | Where-Object { $_.status -eq 'online' }
      }

      if ($onlineRunners.Count -gt 0) { break }

      if ((Get-Date) -lt $deadline) {
        Write-Host "    No online runners yet, retrying in ${pollInterval}s..." -ForegroundColor Gray
        Start-Sleep -Seconds $pollInterval
      }
    } while ((Get-Date) -lt $deadline)

    Assert-Check "GitHub runners registered for $GitHubRepo" ($allRunners.Count -gt 0) 'No self-hosted runners found'
    Assert-Check 'At least one GitHub runner is online' ($onlineRunners.Count -gt 0) "Found $($allRunners.Count) runner(s) but none online"

    foreach ($runner in $onlineRunners) {
      $labels = ($runner.labels | ForEach-Object { $_.name }) -join ', '
      Write-Host "    Runner: $($runner.name) — status: $($runner.status), OS: $($runner.os), labels: [$labels]" -ForegroundColor Gray
    }

    # Check for self-hosted label
    $selfHostedRunners = $onlineRunners | Where-Object { $_.labels.name -contains 'self-hosted' }
    Assert-Check 'Online runner has self-hosted label' ($selfHostedRunners.Count -gt 0) 'No online runner with self-hosted label'
  } catch {
    Assert-Check 'GitHub API reachable' $false $_.Exception.Message
  }
}

# ─── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n$('='*60)" -ForegroundColor White
$summary = "Agent Verification: $pass passed, $fail failed"
Write-Host $summary -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "$('='*60)`n" -ForegroundColor White

if ($fail -gt 0) {
  Write-Host "Agents may need time to bootstrap after deployment (~5 min)." -ForegroundColor Yellow
  Write-Host "Re-run with a longer -TimeoutSeconds if agents are still starting." -ForegroundColor Yellow
}

exit ($fail -gt 0 ? 1 : 0)
