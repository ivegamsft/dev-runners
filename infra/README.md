# Infrastructure

This repo is split into two deployment units:

1. Base infrastructure (`infra/base`): Networking, Key Vault, Managed Identities, Azure Compute Gallery, VM Scale Set (Azure DevOps agents), Single VM (GitHub runner), supporting resources.
2. Image pipeline & image definitions (`infra/images`): Image Definitions & build pipeline (Azure Image Builder) for Windows and Linux agent images.

## Naming Convention

All resource base names derive from these parameters:
- org (short org identifier) e.g. `acme`
- env (environment) e.g. `dev`, `prod`
- loc (Azure region short) e.g. `weu`, `use`
- uniqueSuffix (short random for global uniqueness)

Pattern examples:
- Key Vault: kv-${org}-${env}-${loc}-${uniqueSuffix}
- Gallery: gal${org}${env}${loc}${uniqueSuffix}
- VMSS: vmss-${org}-${env}-ado-${loc}
- GitHub Runner VM: vm-${org}-${env}-gh-${loc}

## Deploy Order

1. Deploy base: creates Key Vault & empty secrets placeholders (or generates runtime values) + identities.
2. Manually insert ADO PAT / GitHub registration token into Key Vault (or use pipeline to set them).
3. Deploy images (build or rebuild). Publish to gallery.
4. Update VMSS/VM model to latest image version (can be automated via pipeline).

## Secrets

Stored in Key Vault:
- ado-pat
- gh-runner-token
- agent-registration-shared (optional)

Access via managed identity with Key Vault access policies / RBAC.
