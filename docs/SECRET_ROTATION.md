# Secret Rotation Runbook

## Automated Rotation
The `rotate-secrets.yml` workflow runs monthly and can be triggered manually.

### Schedule
- **Automatic**: 1st of each month at 06:00 UTC
- **Manual**: Actions tab → "Rotate Runner Bootstrap Secrets" → Run workflow

### Supported Secrets
| Secret | Auto-rotated | Rotation Method |
|--------|-------------|-----------------|
| `admin-password` | Yes | Generate new random password, store in Key Vault |
| `ado-pat` | No | Manual — requires Azure DevOps PAT regeneration |
| `gh-runner-token` | N/A | Ephemeral — fetched dynamically at runner start |

### Force Rotation
Set `forceRotate: true` in the workflow dispatch to bypass the 30-day cooldown.

## Manual Rotation

### admin-password
```powershell
pwsh ./scripts/identity/set-admin-password.ps1 -KeyVaultName <kv-name> -ForceRotate
```

### ado-pat
1. Generate new PAT in Azure DevOps (Organization Settings → Personal Access Tokens)
2. Store in Key Vault:
   ```bash
   az keyvault secret set --vault-name <kv-name> --name ado-pat --value "<new-pat>"
   ```
3. Restart ADO agent VMs to pick up new credential

## Monitoring

### Check Secret Age
```powershell
pwsh ./scripts/identity/check-secret-expiry.ps1 -KeyVaultName <kv-name> -MaxAgeDays 90
```

### Alerts
- The rotation workflow posts a summary to the Actions run
- Secrets older than 90 days are flagged as STALE by the expiry check
- Failed rotations are visible in the Actions tab

## Rollback
If a rotation causes issues:
1. Retrieve the previous secret version: `az keyvault secret list-versions --vault-name <kv> --name <secret>`
2. Set the old version as current: `az keyvault secret set --vault-name <kv> --name <secret> --value <old-value>`
3. Restart affected VMs/VMSS instances
