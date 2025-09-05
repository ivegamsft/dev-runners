# Self-Hosted Runner Images

This folder contains Packer templates for building:

1. Linux GitHub Actions ephemeral runner image (`linux-packer.json`)
2. Windows Azure DevOps self‑hosted agent image (`windows-packer.json`)

Both templates are parameterized via Packer user variables and environment variables so they can run in CI without editing JSON.

---
## 1. Linux GitHub Actions Runner (Ephemeral)
Template: `linux-packer.json`

### Features
- Ubuntu 22.04 (Jammy) base
- Installs: git, curl, jq, Node.js 20, Azure CLI, azd, build essentials, Python, zip/unzip
- Downloads GitHub Actions runner (version via `runner_version` variable)
- Places runner under `/opt/actions-runner`
- Creates `bootstrap.sh` and a `systemd` service `github-runner` (enabled but requires environment injection)
- Ephemeral (`--ephemeral --replace`) runner configuration each start
- Optional Key Vault PAT secret retrieval via managed identity

### Build Variables
Provided by `variables` block (any can be overridden):
| Variable | Env Var | Default / Purpose |
|----------|---------|-------------------|
| `runner_version` | (none) | Version of GH runner (e.g. 2.317.0) |
| `runner_user` | (none) | System user that owns runner files |
| `location` | `PACKER_LOCATION` | Azure region for build |
| `managed_image_rg` | `PACKER_IMAGE_RG` | RG where managed image stored |
| `managed_image_name` | (none) | Output image name |
| `temp_rg` | `PACKER_TEMP_RG` | Temporary Packer RG |
| `vm_size` | `PACKER_VM_SIZE` | Build VM size |
| `tag_org` | `ORG` | Tag inheritance |
| `tag_env` | `ENV` | Tag inheritance |

### Runtime Environment Variables (Injected Post-Provision)
Set (e.g. via cloud-init, VM extension, or scale set Custom Script) before service starts:
- `GH_SCOPE` : `org` or `repo`
- `GH_OWNER` : Organization or user
- `GH_REPO`  : Required only when `GH_SCOPE=repo`
- One of:
  - `GH_PAT` : Personal Access Token (repo / org:admin:read/write runner registration scope)
  - OR `KEYVAULT_NAME` + `SECRET_NAME` (secret contains PAT) and managed identity with `get` on secrets

### PAT Secret Retrieval Logic
If `KEYVAULT_NAME` is set and `GH_PAT` not provided, the bootstrap script:
1. Uses IMDS to get MSI token (`https://vault.azure.net` resource)
2. Calls Key Vault secret endpoint to retrieve PAT
3. Requests a registration token from GitHub REST API
4. Configures ephemeral runner and executes `run.sh`

### Example Build (PowerShell)
```powershell
$env:PACKER_LOCATION='swedencentral'
$env:PACKER_IMAGE_RG='rg-images'
$env:PACKER_TEMP_RG='rg-packer-temp'
$env:PACKER_VM_SIZE='Standard_D4s_v5'
$env:ORG='acme'
$env:ENV='dev'
packer build -var "managed_image_name=linux-gh-runner-$(Get-Date -Format yyyyMMddHHmm)" -var "runner_version=2.317.0" scripts/image/linux-packer.json
```

### Systemd Override / Additional Labels
Edit `/etc/systemd/system/github-runner.service` before baking OR override at runtime to add labels: set `--labels` in `bootstrap.sh` line with `./config.sh`.

---
## 2. Windows Azure DevOps Agent Image
Template: `windows-packer.json`

### Features
- Windows Server 2022 Azure Edition
- Installs: Git, Node.js LTS, VS 2022 Build Tools (VC workload), Azure CLI, azd, CMake, Python 3.12, Chocolatey, Az PowerShell module
- Downloads Azure DevOps agent (version via `agent_version` variable) into `C:\ado-agent`
- Pre-caches some tooling (npm yarn/pnpm, pip upgrade)
- Creates:
  - `configure-run.ps1` (manual invocation script)
  - `bootstrap-agent.ps1` for first boot managed identity + Key Vault PAT retrieval & unattended config
  - Windows service `AdoBootstrap` to run bootstrap automatically

### Build Variables
| Variable | Env Var | Purpose |
|----------|---------|---------|
| `location` | `PACKER_LOCATION` | Azure region |
| `managed_image_rg` | `PACKER_IMAGE_RG` | RG for managed image |
| `managed_image_name` | (none) | Output image name |
| `temp_rg` | `PACKER_TEMP_RG` | Temp build RG |
| `vm_size` | `PACKER_VM_SIZE` | Build VM size |
| `agent_version` | (none) | ADO agent version |
| `agent_root` | (none) | Install directory |
| `tag_org` | `ORG` | Tag |
| `tag_env` | `ENV` | Tag |

### Runtime Environment Variables (Before First Boot Service Start)
- `ADO_ORG_URL` : e.g. `https://dev.azure.com/acme`
- `KEYVAULT_NAME` : Key Vault name containing PAT secret
- `ADO_PAT_SECRET` : Secret name (default `ado-pat`)
- `ADO_POOL` : Target pool (default `Default`)

PAT secret must have scope `AgentPools (Read, Manage)` & `Deployment Groups` if needed; treat with least privilege.

### First Boot Flow
1. Service `AdoBootstrap` starts
2. Retrieves PAT from Key Vault via managed identity
3. Runs `config.cmd` with `--runAsService` to register agent
4. Starts agent service (from agent’s own service registration)

### Example Build (PowerShell)
```powershell
$env:PACKER_LOCATION='swedencentral'
$env:PACKER_IMAGE_RG='rg-images'
$env:PACKER_TEMP_RG='rg-packer-temp'
$env:PACKER_VM_SIZE='Standard_D4s_v5'
$env:ORG='acme'
$env:ENV='dev'
packer build -var "managed_image_name=windows-ado-agent-$(Get-Date -Format yyyyMMddHHmm)" -var "agent_version=3.240.1" scripts/image/windows-packer.json
```

### Optional: Manual Agent Config (Fallback)
If you choose not to use bootstrap service, RDP and run:
```powershell
cd C:\ado-agent
./config.cmd --unattended --url $env:ADO_ORG_URL --pool MyPool --agent $env:COMPUTERNAME --auth pat --token <PAT> --work c:/ado/_work --replace
./run.cmd
```

---
## 3. Publishing to Azure Compute Gallery (Future Phase)
1. Ensure subscription registered for `Microsoft.Compute` preview features if required
2. Create gallery (Bicep param: `createGallery=true` once enabled)
3. After each Packer build, create or update image definition & push version:
   - Linux definition: `linux-agent`
   - Windows definition: `windows-agent`
4. Update infra parameters:
   - `useGalleryImages=true`
   - Provide `linuxImageVersion` / `windowsImageVersion` or leave `latest`

## 4. Base Deployment Toggle Recap
Bicep parameters (`infra/base/parameters.*.json`):
- `createGallery` : actually create gallery resource
- `useGalleryImages` : reference gallery images instead of marketplace base images
- `linuxUsePassword` : temporary fallback for SSH key issues (should be `false` in hardened state)

## 5. Security Considerations
| Area | Guidance |
|------|----------|
| PAT Storage | Store only in Key Vault, never bake into images or templates |
| Managed Identity | Grant only `get` permission (RBAC Secrets User) on Key Vault |
| Ephemeral Runners | Prefer ephemeral GitHub runners to reduce persistence & lateral movement risk |
| Updates | Rebuild images regularly (monthly) with updated base + tooling |
| Logging | Consider enabling Guest VM extension for logging / monitoring agents |
| Outbound Access | Restrict via NSG / Firewall egress rules if feasible |

## 6. Troubleshooting
| Symptom | Likely Cause | Fix |
|---------|--------------|-----|
| GitHub runner never shows online | Missing env vars or PAT secret | Verify `GH_*` vars & Key Vault secret spelling |
| ADO agent stuck unconfigured | Service started before env vars present | Inject env vars & restart `AdoBootstrap` service |
| PAT retrieval fails | MI does not have Key Vault data plane access | Assign Key Vault Secrets User role to VM/scale set identity |
| Image build fails early | Missing env RG variables | Export the required `PACKER_*` env vars |

## 7. Example Runtime Env Injection (Linux VMSS custom script)
```bash
#!/usr/bin/env bash
cat >/etc/profile.d/gh-runner-env.sh <<EOF
export GH_SCOPE=org
export GH_OWNER=acme
export KEYVAULT_NAME=kvacmedevseca1b2
export SECRET_NAME=gh-pat
EOF
systemctl restart github-runner.service
```

## 8. Next Steps
- Integrate Packer builds into CI pipeline
- Automate gallery version creation and replication
- Harden images (CIS baseline, remove unused tooling)
- Add cleanup task to remove stale agents/runners

---
**Note:** Do not commit PATs or secrets. Use Key Vault exclusively and rely on managed identities provisioned by the base Bicep template.
