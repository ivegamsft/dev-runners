# Agent Manifest

This repository keeps a version-controlled manifest so you can audit what automation assets are expected on self-hosted agents and in Copilot custom agents.

The manifest file is:

- `manifests/agent-manifest.json`

It includes:

1. Script inventory from `scripts/**` with size and SHA-256 hashes.
2. Copilot custom agents from `.github/agents/*.agent.md` with SHA-256 hashes.
3. Runner image template metadata and install command hints extracted from:
   - `scripts/image/linux-packer.json`
   - `scripts/image/windows-packer.json`

## Update The Manifest

Run:

```powershell
pwsh ./scripts/manifest/update-agent-manifest.ps1
```

Optional custom output path:

```powershell
pwsh ./scripts/manifest/update-agent-manifest.ps1 -OutputPath ./manifests/agent-manifest.json
```

## Recommended Process

1. Change scripts, custom agents, or runner templates.
2. Run the update script.
3. Commit both code changes and manifest updates together.

## CI Enforcement

Workflow [`.github/workflows/manifest-guard.yml`](../.github/workflows/manifest-guard.yml) regenerates the manifest during CI and fails if [manifests/agent-manifest.json](../manifests/agent-manifest.json) is out of date.