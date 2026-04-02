param(
  [string]$SubscriptionId,
  [string]$ResourceGroup,
  [string]$KeyVaultName,
  [string]$SecretName = 'admin-password',
  [string]$Password,
  [string]$ParametersFile = '..\..\infra\base\parameters.dev.json',
  [int]$Length = 24,
  [switch]$ForceRotate,
  [switch]$ShowPassword
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-AzCli {
  param([string[]]$Args)

  $output = & az @Args
  if ($LASTEXITCODE -ne 0) {
    throw "az command failed: az $($Args -join ' ')"
  }

  $output
}

function New-StrongPassword {
  param([int]$PasswordLength = 24)

  if ($PasswordLength -lt 16) {
    throw 'Password length must be at least 16 characters.'
  }

  $lower = 'abcdefghijkmnopqrstuvwxyz'
  $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
  $digits = '23456789'
  $symbols = '!@#$%^&*()-_=+[]{}:,.?'
  $all = ($lower + $upper + $digits + $symbols).ToCharArray()

  $bytes = New-Object byte[] ($PasswordLength + 16)
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)

  $chars = New-Object System.Collections.Generic.List[char]
  $chars.Add($lower[$bytes[0] % $lower.Length])
  $chars.Add($upper[$bytes[1] % $upper.Length])
  $chars.Add($digits[$bytes[2] % $digits.Length])
  $chars.Add($symbols[$bytes[3] % $symbols.Length])

  for ($i = 4; $i -lt $PasswordLength; $i++) {
    $chars.Add($all[$bytes[$i] % $all.Length])
  }

  for ($i = $chars.Count - 1; $i -gt 0; $i--) {
    $swapIndex = $bytes[($PasswordLength + ($i % 16))] % ($i + 1)
    $tmp = $chars[$i]
    $chars[$i] = $chars[$swapIndex]
    $chars[$swapIndex] = $tmp
  }

  -join $chars
}

if ($SubscriptionId) {
  Invoke-AzCli -Args @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
}

if (-not [System.IO.Path]::IsPathRooted($ParametersFile)) {
  $ParametersFile = Join-Path $PSScriptRoot $ParametersFile
}

if (-not $KeyVaultName) {
  if (-not $ResourceGroup -and (Test-Path $ParametersFile)) {
    $params = Get-Content $ParametersFile -Raw | ConvertFrom-Json
    $p = $params.parameters
    if ($p.org.value -and $p.env.value -and $p.loc.value -and $p.uniqueSuffix.value) {
      $KeyVaultName = ('kv{0}{1}{2}{3}' -f $p.org.value, $p.env.value, $p.loc.value, $p.uniqueSuffix.value).ToLower()
    }
  }

  if (-not $KeyVaultName) {
    if (-not $ResourceGroup) {
      throw 'Provide -KeyVaultName directly, provide -ResourceGroup for discovery, or keep a valid parameters file for name inference.'
    }

    $KeyVaultName = Invoke-AzCli -Args @('keyvault', 'list', '-g', $ResourceGroup, '--query', '[0].name', '-o', 'tsv')
    if (-not $KeyVaultName) {
      throw "No Key Vault found in resource group '$ResourceGroup'."
    }
  }
}

$existing = & az keyvault secret show --vault-name $KeyVaultName --name $SecretName --query id -o tsv 2>$null
if ($existing -and -not $ForceRotate) {
  Write-Host "Secret '$SecretName' already exists in '$KeyVaultName'. Use -ForceRotate to rotate it."
  $result = [pscustomobject]@{
    keyVaultName = $KeyVaultName
    secretName = $SecretName
    changed = $false
  }
  $result | ConvertTo-Json -Depth 3
  exit 0
}

$password = if ($Password) { $Password } else { New-StrongPassword -PasswordLength $Length }
Invoke-AzCli -Args @('keyvault', 'secret', 'set', '--vault-name', $KeyVaultName, '--name', $SecretName, '--value', $password, '--output', 'none') | Out-Null

$verify = & az keyvault secret show --vault-name $KeyVaultName --name $SecretName --query id -o tsv 2>$null
if (-not $verify) {
  throw "Failed to verify secret '$SecretName' in '$KeyVaultName'."
}

$result = [pscustomobject]@{
  keyVaultName = $KeyVaultName
  secretName = $SecretName
  changed = $true
}

if ($ShowPassword) {
  # Optional for one-time bootstrap use; avoid enabling in CI logs.
  $result | Add-Member -NotePropertyName password -NotePropertyValue $password
}

$result | ConvertTo-Json -Depth 3
