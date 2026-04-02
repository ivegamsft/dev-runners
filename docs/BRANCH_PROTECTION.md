# Branch Protection Policy

## Protected Branch: `main`

### Required Reviews
- Minimum 1 approving review before merge
- Stale reviews are dismissed on new pushes

### Required Status Checks
All of the following checks must pass before merge:

| Check | Workflow | Purpose |
|-------|----------|---------|
| `analyze` | `codeql.yml` | CodeQL security analysis for Actions |
| `bicep-lint` | `security-infra.yml` | Bicep template validation |
| `powershell-lint` | `security-infra.yml` | PSScriptAnalyzer on all scripts |
| `verify-manifest` | `manifest-guard.yml` | Manifest consistency enforcement |
| `actionlint` | `workflow-security.yml` | GitHub Actions workflow linting |
| `pin-check` | `workflow-security.yml` | SHA pinning for 3rd-party actions |
| `sbom-and-scan` | `sbom-vuln-scan.yml` | SBOM generation and vulnerability scan |

### Additional Rules
- Branches must be up-to-date before merge (`strict: true`)
- Rules enforced for administrators
- Force pushes blocked
- Branch deletion blocked

### Setup
```powershell
pwsh ./scripts/identity/configure-branch-protection.ps1 -Owner <org> -Repo dev-runners
```

Preview without applying:
```powershell
pwsh ./scripts/identity/configure-branch-protection.ps1 -Owner <org> -Repo dev-runners -WhatIf
```
