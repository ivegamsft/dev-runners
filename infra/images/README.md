# Image Deployment

This module defines image definitions only. Image versions are produced by pipelines using Azure Image Builder or Packer then imported into the Compute Gallery.

## Flow
1. Deploy `infra/images/main.bicep` after base to create image definition shells.
2. Pipeline builds a temporary managed image (or SIG version directly with AIB) for Linux & Windows.
3. Pipeline creates gallery image version (naming: `YYYY.MM.DD.N`).
4. Base VMSS/VM updated (manual or pipeline) to latest version.

## Recommended Gallery Version Pattern
`$(date -u +%Y.%m.%d).$(Build.BuildID)` or similar.

## Parameters to Provide
- galleryName: output from base deployment.
- linuxImageDefinitionName / windowsImageDefinitionName if overridden.

## Pipelines
Store secrets (PAT, tokens) in Key Vault and reference via variable groups or Azure DevOps KeyVault task.
