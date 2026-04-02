# Deployment Scripts

## Base Infrastructure
```
pwsh ./deploy-base.ps1 -SubscriptionId <subId> -ResourceGroup rg-acme-dev-sec -Location swedencentral
```
Add -WhatIf to preview.

## Image Definitions
```
pwsh ./deploy-images.ps1 -SubscriptionId <subId> -ResourceGroup rg-acme-dev-sec -Location swedencentral
```

## Alternate Regions (Capacity Failover)
If `swedencentral` capacity blocks creation, switch to `northcentralus` or another approved region:
1. Update parameters files `location`, `loc` (e.g. `ncu`) and gallery name accordingly.
2. Update resource group name (e.g. `rg-acme-dev-ncu`).
3. Re-run scripts.

## After Base Deployment
Fetch outputs:
```
az deployment group show -g rg-acme-dev-sec -n <baseDeploymentName> --query properties.outputs
```
Use `computeGalleryName` for the images parameter file if different.

## Create / Rotate Admin Password In Key Vault
Generate a strong password and write it to `admin-password` in the resource group's Key Vault:

```
pwsh ../identity/set-admin-password.ps1 -SubscriptionId <subId> -ResourceGroup rg-acme-dev-sec
```

Rotate an existing secret:

```
pwsh ../identity/set-admin-password.ps1 -SubscriptionId <subId> -ResourceGroup rg-acme-dev-sec -ForceRotate
```
