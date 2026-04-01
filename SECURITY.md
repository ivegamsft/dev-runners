# Security Policy

## Supported Versions

This repository tracks infrastructure and automation on the `main` branch.

| Version | Supported |
| ------- | --------- |
| main    | Yes       |

## Reporting a Vulnerability

Do not open public issues for suspected vulnerabilities or leaked credentials.

Use one of these channels:

1. GitHub private vulnerability reporting for this repository.
2. Direct contact with repository maintainers.

When reporting, include:

1. A short description of the issue and impact.
2. Steps to reproduce.
3. Affected files, workflows, or infrastructure components.
4. Any known mitigations.

If the report contains secret material, redact sensitive values and provide only fingerprints or partial values.

## Response Process

1. Triage and acknowledgement target: 3 business days.
2. Initial severity assessment and mitigation plan.
3. Remediation in infrastructure code, workflows, or scripts.
4. Validation through repository security scans and workflow checks.
5. Coordinated disclosure after remediation, when applicable.

## Secret Handling Requirements

1. Never commit plaintext credentials, tokens, private keys, or connection strings.
2. Use GitHub Actions secrets and Azure Key Vault for runtime secret retrieval.
3. Prefer OIDC and managed identities over static credentials.
4. Rotate credentials immediately if exposure is suspected.