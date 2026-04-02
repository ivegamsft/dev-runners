# Copilot Instructions — dev-runners

## What This Repo Does

Infrastructure-as-code for self-hosted Azure DevOps agents (Linux VMSS) and a GitHub Actions runner VM (Windows). Uses Bicep for IaC, Packer for image builds, and GitHub Actions workflows with OIDC authentication against Azure.

## Architecture

```
infra/base/main.bicep        ← Single monolithic template: KV, gallery, identities, networking, VMSS, VM, RBAC
infra/images/main.bicep       ← Image definitions in Azure Compute Gallery (linux-agent, windows-agent)
infra/deploy/main.bicep       ← Thin wrapper that calls base with useGalleryImages forced true
scripts/                      ← All PowerShell (.ps1) — no Bash scripts in this repo
manifests/agent-manifest.json ← Auto-generated inventory of scripts, agents, and image templates
```

**Deployment flow:** deploy base (marketplace images) → build Packer images → publish to gallery → redeploy base with gallery images.

**Naming formula** — all resource names derive from four params:
- `org`, `env`, `loc` (short region code), `uniqueSuffix`
- Examples: `kv${org}${env}${loc}${uniqueSuffix}`, `vmss-${org}-${env}-ado-${loc}`

## Lint & Validate Commands

Bicep lint (builds every `.bicep` file to check for errors):
```powershell
Get-ChildItem -Recurse -Filter *.bicep | ForEach-Object { az bicep build --file $_.FullName }
```

PowerShell lint (all scripts):
```powershell
Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
Invoke-ScriptAnalyzer -Path ./scripts -Recurse -ReportSummary
```

Lint a single PowerShell file:
```powershell
Invoke-ScriptAnalyzer -Path ./scripts/deploy/deploy-base.ps1
```

Workflow lint:
```powershell
actionlint
```

There are no unit test suites. Validation is done via `scripts/validate/validate-base.ps1` against a live Azure deployment.

Run regression tests for all sprints:
```powershell
pwsh ./tests/sprint1-tests.ps1 && pwsh ./tests/sprint2-tests.ps1 && pwsh ./tests/sprint3-tests.ps1
```

## Key Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `deploy-base.yml` | Manual dispatch | Deploy/update core infra |
| `build-images.yml` | Push to `main` (scripts/image/**, infra/images/**) or manual | Build & publish Packer images with CIS checks + signing |
| `deploy-from-gallery.yml` | Manual dispatch | Deploy using latest gallery image versions (with provenance verification) |
| `rotate-secrets.yml` | Monthly schedule or manual | Rotate Key Vault bootstrap secrets |
| `manifest-guard.yml` | PR/push | Fails if `agent-manifest.json` is stale |
| `security-infra.yml` | PR/push | Bicep lint + PSScriptAnalyzer |
| `workflow-security.yml` | PR/push (workflow changes) | actionlint + SHA-pin check for 3rd-party actions |
| `sbom-vuln-scan.yml` | PR/push | CycloneDX SBOM + Trivy vulnerability scan |
| `codeql.yml` | Push/PR/weekly | CodeQL analysis for Actions workflows |

## Conventions

### Bicep

- Parameters use lower camelCase: `adminUsername`, `uniqueSuffix`, `enableGhPublicIp`.
- Secrets are marked `@secure()`. Constrained params use `@allowed([...])` or `@minLength`/`@maxLength`.
- Tags are standardized on every resource: `org`, `env`, `loc`, `system: 'build-agents'`.
- Conditional resource creation uses bool params (e.g., `createGallery`, `useGalleryImages`).
- RBAC assignment names use `guid(...)` for determinism.
- The repo uses a single-template pattern (not Bicep modules) for `infra/base/main.bicep`.

### PowerShell Scripts

- All scripts begin with `Set-StrictMode -Version Latest` and `$ErrorActionPreference = 'Stop'`.
- Paths are resolved relative to script location: `Join-Path $PSScriptRoot ...`.
- Temp files are cleaned up in `finally` blocks.
- Secure strings are used for passwords; plain text conversion is scoped as tightly as possible.
- Logging uses `Write-Host`, sometimes with `-ForegroundColor`.
- Machine-readable output is JSON (e.g., `set-admin-password.ps1`).

### Auth & Secrets

- **OIDC is the standard** — workflows use `azure/login@v2` with federated credentials, no client secrets.
- All workflows set `permissions: id-token: write` for OIDC.
- Secrets go in Azure Key Vault with RBAC (`Key Vault Secrets User` role assigned to managed identities).
- Required GitHub repo secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `ADMIN_SSH_PUBLIC_KEY`.
- `adminPassword` is never committed — workflows generate it dynamically and store in Key Vault.

### Environment Config

`env/dev.json` is the single source of truth for environment-specific values. Workflows load it via `jq` into `$GITHUB_ENV`; scripts load it via an `$EnvConfig` parameter. To add a new environment, create `env/<name>.json`.

### Network Security

The Bicep template includes an NSG (`nsg-{org}-{env}-agents-{loc}`) with default-deny egress. See `docs/EGRESS_POLICY.md` for allowed traffic and the exception process.

### Image Build Integrity

- Packer templates verify SHA256 checksums for downloaded binaries (see `scripts/image/checksums.json`).
- CIS benchmark checks run inside images during build; required failures block publication.
- Build outputs are signed with cosign (keyless OIDC); deploy workflows verify provenance.
- Run `pwsh scripts/image/update-checksums.ps1` after version bumps.

### Manifest Guard

The file `manifests/agent-manifest.json` is auto-generated — never edit it by hand. Regenerate after changing scripts, agents, or Packer templates:
```powershell
pwsh ./scripts/manifest/update-agent-manifest.ps1
```
CI enforces this via `manifest-guard.yml`.

### Workflow Security

Third-party GitHub Actions must be pinned to a full commit SHA. Allowed orgs (tag-pinning OK): `actions/`, `github/`, `azure/`, `hashicorp/`.
