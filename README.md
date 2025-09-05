# Dev Runners Infrastructure

End-to-end setup for self-hosted Azure DevOps agents (Linux VM Scale Set) and GitHub Actions runner VM (Windows) with:
- Bicep IaC (`infra/base`, `infra/images`)
- Packer image builds published to an Azure Compute Gallery
- GitHub Actions workflows using OIDC (no client secret)
- Managed Identities + Key Vault RBAC for secret retrieval at runtime

## Workflows
| Workflow | Purpose |
|----------|---------|
| `deploy-base.yml` | Deploy / update core infrastructure (network, KV, identities, VMSS, GH runner VM, gallery). |
| `build-images.yml` | Build & publish Linux / Windows agent images to the gallery. |
| `deploy-from-gallery.yml` | (If present) Example deploying infra using existing gallery versions only. |

## Required Repository Secrets
(Configure in GitHub: Settings → Secrets and variables → Actions → New repository secret)

| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_ID` | App registration (federated) client ID for OIDC login. Also passed to Bicep param `githubOidcClientId`. |
| `AZURE_TENANT_ID` | Azure AD / Entra tenant ID. |
| `AZURE_SUBSCRIPTION_ID` | Target subscription ID. |
| `ADMIN_SSH_PUBLIC_KEY` | SSH public key (ed25519 or RSA) for Linux VMSS agents. |
| `ADMIN_PASSWORD` | Windows admin password (temporarily stored in Key Vault). Strong password recommended; rotate post-deploy. |

Optional (only if you decide to fall back to secret-based login instead of OIDC):
| Secret | Description |
|--------|-------------|
| `AZURE_CLIENT_SECRET` | Client secret for the SP (NOT needed with OIDC). |

## Optional Future Secrets (placed in Key Vault after deploy)
| KV Secret Name | Purpose |
|----------------|---------|
| `ado-pat` | Azure DevOps Personal Access Token for agent registration (if you use PAT-based bootstrap). |
| `gh-runner-token` | GitHub runner registration token (ephemeral; better to fetch dynamically). |
| `admin-username` | Stored automatically from `adminUsername` param. |
| `admin-password` | Stored automatically when supplied. |

## Environment Variables (Defined in Workflows)
These are set in each workflow `env:` block. Adjust to match your naming strategy.

| Var | Meaning | Example |
|-----|---------|---------|
| `ORG` | Short org code | `acme` |
| `ENV` | Environment | `dev` |
| `LOCATION` | Azure region | `swedencentral` |
| `LOC` | Short region code used in names | `sec` |
| `UNIQUE_SUFFIX` | Random suffix for global uniqueness | `a1b2` |
| `RESOURCE_GROUP` | Resource group for base + gallery | `rg-acme-dev-sec` |
| `GALLERY_NAME` | Compute Gallery name (must match Bicep) | `galacmedevseca1b2` |
| `PACKER_TEMP_RG` | Temp RG for Packer (if used) | `rg-packer-temp` |
| `PACKER_VM_SIZE` | Build VM size for image builds | `Standard_D4s_v5` |

## Bicep Parameters (Key Ones)
| Parameter | Driven By | Notes |
|-----------|-----------|-------|
| `org`, `env`, `loc`, `uniqueSuffix` | Workflow env vars | Naming + uniqueness. |
| `adminUsername` | Hard-coded in workflow (`agentadmin`) | Change if needed. |
| `adminSshPublicKey` | Secret reference | Provide valid public key. |
| `adminPassword` | Secret reference | Only needed for Windows / fallback. |
| `useGalleryImages` | Workflow dispatch input | Set true after images published. |
| `enableGhPublicIp` | Workflow dispatch input | Dev convenience; disable for prod. |
| `githubOidcClientId` | Secret `AZURE_CLIENT_ID` | Surfaced as output. |

## OIDC Setup
Use helper script:
```powershell
pwsh ./scripts/identity/setup-github-oidc.ps1 \ 
  -DisplayName gh-oidc-acme-dev \ 
  -GitHubOrg <yourOrg> \ 
  -GitHubRepo dev-runners \ 
  -Branch main \ 
  -ResourceGroup rg-acme-dev-sec \ 
  -Roles Contributor
```
Outputs appId – store as `AZURE_CLIENT_ID`.

## Typical Flow
1. Run `Deploy Base Infrastructure` workflow (keep `useGalleryImages=false` initially).  
2. Run `Build and Publish Agent Images` workflow (produces gallery versions).  
3. Re-run `Deploy Base Infrastructure` with `useGalleryImages=true` to switch VMSS/VM to gallery images.  
4. (Optional) Scale VMSS, rotate images, or add more identities/roles.  

## Security Notes
- Remove `AZURE_CLIENT_SECRET` after confirming OIDC works.
- Limit federated credential subjects to required branches.
- Rotate `ADMIN_PASSWORD` and then disable storage of it if using only SSH + Windows password rotation policies.
- Consider splitting roles instead of broad `Contributor`.

## Cleanup
```bash
az group delete -n <resourceGroup> --yes --no-wait
```

## Troubleshooting
| Issue | Hint |
|-------|------|
| Gallery version conflict | Version generation loops; ensure clock/timezone OK. |
| Key Vault RBAC delay | Wait a minute after first deploy before accessing secrets. |
| OIDC login fails | Verify federated credential subject matches `repo:ORG/REPO:ref:refs/heads/main`. |

---
Maintained by Platform Engineering.
