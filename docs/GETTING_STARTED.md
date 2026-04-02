# Getting Started

End-to-end guide: bootstrap → deploy → verify → cleanup.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| PowerShell | 7+ | `winget install Microsoft.PowerShell` / [install-powershell](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) |
| Azure CLI | 2.50+ | `winget install Microsoft.AzureCLI` / [install-az](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| GitHub CLI | 2.0+ | `winget install GitHub.cli` / [install-gh](https://cli.github.com/) |
| jq | 1.6+ | `winget install jqlang.jq` / [install-jq](https://jqlang.github.io/jq/download/) |
| Packer | 1.9+ | `winget install Hashicorp.Packer` / [install-packer](https://developer.hashicorp.com/packer/install) |

Login before starting:
```powershell
az login
gh auth login
```

## Quick Start (Bootstrap)

The bootstrap script handles everything from zero. Only 4 params are required — everything else has smart defaults or is auto-generated:

```powershell
pwsh scripts/bootstrap.ps1 `
  -Org myorg `
  -SubscriptionId 00000000-0000-0000-0000-000000000000 `
  -GitHubRepo yourorg/dev-runners `
  -AdminSshPublicKeyFile ~/.ssh/id_rsa.pub
```

Auto-derived/generated:
- **Env** → `dev` (override with `-Env prod`)
- **Location** → from `az config` or `eastus2` (override with `-Location westeurope`)
- **Loc** → CAF abbreviation from Location (e.g. `eastus2` → `eus2`, `westeurope` → `we`)
- **UniqueSuffix** → random 4-char alphanumeric (override with `-UniqueSuffix x7k2`)
- **AdminUsername** → `azureadmin` (override with `-AdminUsername youruser`)
- **ResourceGroup** → `rg-{org}-{env}-{loc}` (CAF standard)
- **GalleryName** → `gal{org}{env}{loc}{suffix}` (no hyphens, Azure requirement)

What it does:
1. Checks prerequisites (az, gh, pwsh, jq, packer)
2. Creates `env/dev.json` and `infra/*/parameters.local.json` from samples
3. Creates the Azure resource group with standard tags
4. Sets up OIDC (Entra app + federated credential + RBAC)
5. Configures GitHub repository variables and secrets
6. Runs the first base infrastructure deployment

Use `-WhatIf` to preview without making changes. Use `-SkipDeploy` to configure without deploying.

## Manual Setup (Without Bootstrap)

### 1. Local Config Files

```powershell
# Copy samples and fill in your values
cp env/sample.json env/dev.json
cp infra/base/parameters.sample.json infra/base/parameters.local.json
cp infra/images/parameters.sample.json infra/images/parameters.local.json
```

### 2. GitHub Repository Variables

Go to **Settings → Secrets and variables → Variables** and set:

| Variable | Example |
|----------|---------|
| `ORG` | `myorg` |
| `ENV` | `dev` |
| `LOCATION` | `eastus2` |
| `LOC` | `eus2` |
| `UNIQUE_SUFFIX` | `a1b2` |
| `RESOURCE_GROUP` | `rg-myorg-dev-eus2` |
| `GALLERY_NAME` | `galmyorgdeveus2a1b2` |
| `PACKER_TEMP_RG` | `rg-packer-temp` |
| `PACKER_VM_SIZE` | `Standard_D4s_v5` |
| `ADMIN_USERNAME` | `azureadmin` |

### 3. GitHub Repository Secrets

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | Entra app registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription |
| `ADMIN_SSH_PUBLIC_KEY` | SSH public key for Linux VMs |

### 4. OIDC Setup

```powershell
pwsh scripts/identity/setup-github-oidc.ps1 `
  -DisplayName gh-oidc-myorg-dev `
  -GitHubOrg yourorg `
  -GitHubRepo dev-runners `
  -ResourceGroup rg-myorg-dev-eus2 `
  -Roles Contributor,'User Access Administrator'
```

> **Why User Access Administrator?** The Bicep template creates RBAC role assignments
> (Key Vault Secrets User for managed identities). `Contributor` alone cannot write
> role assignments — `User Access Administrator` is required.

## Deployment Flow

```
bootstrap.ps1  →  deploy-base (marketplace images)
                        ↓
               build-images (Packer + CIS + signing)
                        ↓
               deploy-from-gallery (verified images)
```

1. **Base deploy** — creates KV, gallery, identities, networking, VMSS, VM
2. **Image build** — builds hardened Linux/Windows images with CIS checks
3. **Gallery deploy** — redeploys using verified gallery images

## Verification

```powershell
# Full verification (offline + Azure)
pwsh scripts/verify-environment.ps1 `
  -SubscriptionId 00000000-... `
  -ResourceGroup rg-myorg-dev-eus2

# Offline only (no Azure required)
pwsh scripts/verify-environment.ps1 -SkipAzure

# Static regression tests
pwsh tests/sprint1-tests.ps1
pwsh tests/sprint2-tests.ps1
pwsh tests/sprint3-tests.ps1
pwsh tests/parameter-tests.ps1
```

The verify script checks:
- Sample files exist with placeholders (no hardcoded values)
- All static regression tests pass (188+ assertions)
- Manifest is up to date
- No secrets in tracked files
- (With Azure) Resource group, Key Vault, Gallery, Identities, VMSS, VM, NSG

## Cleanup

```powershell
# Preview what would be deleted
pwsh scripts/cleanup.ps1 `
  -SubscriptionId 00000000-... `
  -Org myorg -Env dev -Loc eus2 -UniqueSuffix a1b2 `
  -WhatIf

# Delete Azure resources + purge soft-deleted Key Vault
pwsh scripts/cleanup.ps1 `
  -SubscriptionId 00000000-... `
  -Org myorg -Env dev -Loc eus2 -UniqueSuffix a1b2

# Full cleanup (Azure + OIDC app + GitHub config)
pwsh scripts/cleanup.ps1 `
  -SubscriptionId 00000000-... `
  -Org myorg -Env dev -Loc eus2 -UniqueSuffix a1b2 `
  -GitHubRepo yourorg/dev-runners `
  -IncludeOidc -IncludeGitHub -Force
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `env/dev.json not found` | Run `bootstrap.ps1` or copy `env/sample.json` |
| `parameters.local.json not found` | Run `bootstrap.ps1` or copy from `*.sample.json` |
| OIDC login fails in workflow | Check `AZURE_CLIENT_ID` secret matches the Entra app |
| `adminPassword` too short | Workflows generate 24-char passwords; don't set manually |
| Manifest guard fails | Run `pwsh scripts/manifest/update-agent-manifest.ps1` |
| PSScriptAnalyzer errors | Run `Invoke-ScriptAnalyzer -Path ./scripts -Recurse` |
