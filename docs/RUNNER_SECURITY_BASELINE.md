# Runner Security Baseline

This checklist tracks controls for a secure private runner build and deployment process.

## Enabled In Repository

1. Code scanning workflow: [../.github/workflows/codeql.yml](../.github/workflows/codeql.yml)
2. Infra security lint: [../.github/workflows/security-infra.yml](../.github/workflows/security-infra.yml)
3. Manifest integrity guard: [../.github/workflows/manifest-guard.yml](../.github/workflows/manifest-guard.yml)
4. Workflow lint and pinning checks: [../.github/workflows/workflow-security.yml](../.github/workflows/workflow-security.yml)
5. SBOM and CVE scan: [../.github/workflows/sbom-vuln-scan.yml](../.github/workflows/sbom-vuln-scan.yml)

## Recommended Next Controls

1. Sign artifacts and attest provenance (Sigstore keyless + SLSA provenance).
2. Verify signatures and provenance before deployment.
3. Pin all third-party GitHub Actions to commit SHAs.
4. Validate checksums for downloaded runner/agent binaries in packer scripts.
5. Enforce CIS benchmark checks during image build (Linux and Windows).
6. Restrict outbound egress from runners and enforce private networking where possible.
7. Use ephemeral runners only and avoid persistent credential material on disk.
8. Enable branch protections with required security workflow checks.
9. Add policy-as-code checks for Bicep and workflow configuration.
10. Add periodic secret rotation with alerting and audit logs.

## Operational Notes

1. Keep OIDC-based auth as default; avoid client secrets.
2. Store admin bootstrap password only in Key Vault and rotate after first use.
3. Rebuild runner images regularly and treat image updates as patch windows.