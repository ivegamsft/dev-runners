## GitHub OIDC Configuration

This repo supports secretless authentication to Azure using GitHub OpenID Connect (OIDC) federation.

### 1. Create / Update Federated Credential
Run the helper script (requires directory write permissions):
```powershell
pwsh ./scripts/identity/setup-github-oidc.ps1 \ 
  -DisplayName gh-oidc-acme-dev \ 
  -GitHubOrg ivegamsft \ 
  -GitHubRepo dev-runners \ 
  -Branch main \ 
  -ResourceGroup rg-acme-dev-sec \ 
  -Roles Contributor
```

### 2. Configure GitHub Secrets
Set:
- AZURE_CLIENT_ID = <appId>
- AZURE_TENANT_ID = <tenant id>
- AZURE_SUBSCRIPTION_ID = <subscription id>

Remove:
- AZURE_CLIENT_SECRET

### 3. Workflow Permissions
Workflows already declare `id-token: write` allowing OIDC tokens.

### 4. Subject Mapping
Default subject: `repo:ORG/REPO:ref:refs/heads/BRANCH`.
Use `-Subject` parameter for tags/environments.

### 5. Bicep Integration
Parameter `githubOidcClientId` surfaces client ID (optional). Output: `githubOidcClientIdOut`.

### 6. Least Privilege
Replace `Contributor` with discrete roles if desired.

### 7. Multiple Branches
Create additional federated credentials (unique `name`) for each branch.

---
Monitor usage via Entra ID sign-in logs for the application.