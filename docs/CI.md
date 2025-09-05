## CI/CD Workflows Overview

This repository includes two GitHub Actions workflows that automate the full lifecycle of the self‑hosted build infrastructure:

1. build-images.yml – Builds and publishes Linux (GitHub Actions runner) and Windows (Azure DevOps agent) images to the Azure Compute Gallery.
2. deploy-from-gallery.yml – Deploys the base infrastructure (Key Vault, identities, networking, VM Scale Set, GitHub runner VM) using the latest published gallery image versions.

### 1. Image Build Workflow
Path: `.github/workflows/build-images.yml`

Key stages:
- Deploy (idempotent) the gallery image definitions (`infra/images/main.bicep`).
- Matrix Packer build (linux, windows) using the Azure `azure-arm` builder.
- Auto‑generates a compliant three‑segment gallery version (Year.Month.Patch) where Patch starts at calendar day and increments if already taken.
- Publishes versions directly to the Shared Image Gallery.

Important environment / secrets:
- AZURE_CLIENT_ID / AZURE_CLIENT_SECRET / AZURE_TENANT_ID / AZURE_SUBSCRIPTION_ID (Service Principal with rights to RG + gallery).
- (Optional) Use OIDC + federated credential instead of client secret (remove client-secret input and secret; update docs accordingly).

### 2. Deployment Workflow
Path: `.github/workflows/deploy-from-gallery.yml`

Performs:
- Resolves latest linux & windows gallery versions.
- Creates a deployment parameter file dynamically.
- Runs group deployment for `infra/deploy/main.bicep` (which wraps `infra/base/main.bicep` with `useGalleryImages=true`).

Required secrets:
- ADMIN_SSH_PUBLIC_KEY – Public key for Linux agents.
- ADMIN_PASSWORD – (If used) bootstrap Windows admin password (rotate later / consider Key Vault reference pattern).

Shared env (hard‑coded in workflows – adjust as needed):
- ORG / ENV / LOCATION / LOC / UNIQUE_SUFFIX – naming & tagging inputs.
- RESOURCE_GROUP – single RG hosting all assets.
- GALLERY_NAME – must match naming convention employed during initial base deployment.

### Security Notes
- PATs for GitHub and Azure DevOps are NOT used during image build; they are fetched at runtime via managed identity from Key Vault.
- Service Principal should have least privilege (contributor on target RG + ability to read/write gallery, network, compute, key vault role assignments). Consider splitting build and deploy principals for stricter separation.

### Customization Points
- Version Strategy: Modify the bash loop in `build-images.yml` if you prefer semantic (e.g., Year.Month.Sequence) instead of Day.
- VM Sizes: Overridable in deployment workflow dispatch inputs.
- Add Replication Regions: Extend `replication_regions` array inside packer templates or parametrize via env var.

### Adding OIDC (Secretless) Authentication (Optional)
1. Create federated credential on the Azure AD application bound to repo & environment / branch.
2. Remove `client-secret` from `azure/login` steps.
3. Delete `AZURE_CLIENT_SECRET` secret.
4. Ensure workflow permissions: `id-token: write` (already set).

### Next Steps / Enhancements
- Automated cleanup of stale image versions (retain last N).
- Add scheduled monthly rebuild trigger (`schedule:` cron) for patching cadence.
- Integrate image vulnerability scanning (e.g., Trivy) as a post-build job.
- Publish SBOM / manifest for installed tooling.
- Add NSG / firewall deployments to further restrict egress.

---
Update both workflows when changing base naming parameters to keep gallery + infra alignment.
