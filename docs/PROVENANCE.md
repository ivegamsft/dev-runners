# Build Provenance & Artifact Signing

## Overview
Runner image builds generate SLSA-style provenance attestations signed with Sigstore/cosign using GitHub OIDC (keyless signing).

## What Gets Signed
Each Packer image build produces:
- `provenance-<image>.json` — SLSA provenance document
- `provenance-<image>.sig` — Cosign signature
- `provenance-<image>.crt` — Signing certificate (ephemeral, OIDC-bound)

## Signing Process
1. Build workflow generates provenance JSON with build metadata
2. Cosign signs the blob using GitHub OIDC identity (keyless)
3. Signature + certificate uploaded as workflow artifacts

## Verification
The deploy-from-gallery workflow verifies provenance before deployment:
1. Downloads provenance artifacts from the latest successful build
2. Verifies signature using cosign with certificate identity matching
3. Logs verification status (warning if not found, does not block deployment yet)

## Manual Verification
```bash
cosign verify-blob \
  --certificate provenance-linux.crt \
  --signature provenance-linux.sig \
  --certificate-identity-regexp "https://github.com/<owner>/<repo>/" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  provenance-linux.json
```
