<#
.SYNOPSIS
  CIS-inspired hardening checks for Windows Server 2022 runner images.
  Returns JSON report; exits non-zero on required control failures.
#>
param([string]$ReportFile = "$env:TEMP\cis-check-windows.json")

$ErrorActionPreference = 'Stop'
$pass = 0; $fail = 0; $warn = 0
$results = @()

function Test-CIS {
  param([string]$Id, [string]$Description, [string]$Severity, [bool]$Condition)
  $status = if ($Condition) { $script:pass++; 'PASS' }
            elseif ($Severity -eq 'required') { $script:fail++; 'FAIL' }
            else { $script:warn++; 'WARN' }
  $script:results += @{ id = $Id; description = $Description; severity = $Severity; status = $status }
}

# Account policies
Test-CIS -Id 'CIS-1.1' -Description 'Guest account is disabled' -Severity 'required' `
  -Condition ((Get-LocalUser -Name Guest -ErrorAction SilentlyContinue).Enabled -eq $false)

Test-CIS -Id 'CIS-1.2' -Description 'Administrator account is renamed from default' -Severity 'recommended' `
  -Condition ((Get-LocalUser | Where-Object { $_.SID -like '*-500' }).Name -ne 'Administrator')

# Audit policies
$auditPol = auditpol /get /category:* 2>$null | Out-String
Test-CIS -Id 'CIS-2.1' -Description 'Logon events auditing enabled' -Severity 'required' `
  -Condition ($auditPol -match 'Logon.*Success')

# Network hardening
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
Test-CIS -Id 'CIS-3.1' -Description 'Windows Firewall Domain profile enabled' -Severity 'required' `
  -Condition (($fw | Where-Object { $_.Name -eq 'Domain' }).Enabled -eq $true)
Test-CIS -Id 'CIS-3.2' -Description 'Windows Firewall Public profile enabled' -Severity 'required' `
  -Condition (($fw | Where-Object { $_.Name -eq 'Public' }).Enabled -eq $true)

# Services
Test-CIS -Id 'CIS-4.1' -Description 'Remote Registry service disabled' -Severity 'recommended' `
  -Condition ((Get-Service RemoteRegistry -ErrorAction SilentlyContinue).StartType -eq 'Disabled')
Test-CIS -Id 'CIS-4.2' -Description 'Windows Remote Management running (required for agent)' -Severity 'required' `
  -Condition ((Get-Service WinRM -ErrorAction SilentlyContinue).Status -eq 'Running')

# Security features
Test-CIS -Id 'CIS-5.1' -Description 'Windows Defender is enabled' -Severity 'required' `
  -Condition ((Get-MpComputerStatus -ErrorAction SilentlyContinue).AntivirusEnabled -eq $true)
Test-CIS -Id 'CIS-5.2' -Description 'PowerShell script block logging enabled' -Severity 'recommended' `
  -Condition ((Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' -Name EnableScriptBlockLogging -ErrorAction SilentlyContinue).EnableScriptBlockLogging -eq 1)

# TLS
Test-CIS -Id 'CIS-6.1' -Description 'TLS 1.2 is enabled' -Severity 'required' `
  -Condition ((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client' -Name Enabled -ErrorAction SilentlyContinue).Enabled -ne 0)

$report = @{
  summary = @{ pass = $pass; fail = $fail; warn = $warn; total = ($pass + $fail + $warn) }
  checks = $results
} | ConvertTo-Json -Depth 4

$report | Out-File $ReportFile -Encoding utf8
Write-Host "CIS Check Results: $pass pass, $fail fail, $warn warn"
Write-Host $report

if ($fail -gt 0) {
  Write-Error "FAILED: $fail required controls did not pass"
  exit 1
}
