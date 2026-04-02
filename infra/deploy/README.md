# Stage 3 Deployment (Runner Infra From Gallery Images)

This stage consumes image version values produced by the image build stage (Packer) and deploys the base infrastructure (`../base/main.bicep`) using those gallery versions.

## Expected Inputs
Provide (via parameters file or CLI):
- org, env, location, loc, uniqueSuffix (same naming seed as earlier stages)
- adminUsername, adminSshPublicKey, adminPassword (secure)
- linuxImageVersion: Gallery version string for `linux-agent` (e.g. `2025.09.05.1`)
- windowsImageVersion: Gallery version string for `windows-agent`
- useGalleryImages: must be `true`

## Files
- `main.bicep` - orchestrator referencing `../base/main.bicep`
- `parameters.sample.json` - template for required parameters.

## Usage
```
cp infra/deploy/parameters.sample.json infra/deploy/parameters.local.json
# Edit parameters.local.json with your values
az deployment group create -g <rg> -f infra/deploy/main.bicep -p @infra/deploy/parameters.local.json
```

`parameters.local.json` should be derived from `parameters.sample.json` and filled with actual gallery version numbers output by your build pipeline. Local parameter files are gitignored.
