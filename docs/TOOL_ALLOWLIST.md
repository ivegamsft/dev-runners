# Copilot Agent Tool Allow List

Purpose: Minimize tool activation to reduce noise, latency, and unintended side-effects for this Azure build agents project.

## Core (Always Enabled)
| Category | Purpose |
|----------|---------|
| Azure Deployment & Configuration | Deploy Bicep (base + images) and future image builder templates |
| Azure Resource Management | Manage resource groups, identities, VMSS, gallery, quotas |
| Azure Key Vault Management | Create/update secrets (PAT, tokens, admin credentials) |
| GitHub Repository Management | File edits, branches, commits |
| GitHub Pull Request Management | PR creation/review/update |
| GitHub Workflow Management | GitHub Actions runs for image builds & rollouts |

## Conditional (Enable Only When Needed)
| Category | Trigger |
|----------|---------|
| Azure Monitoring & Logging | After adding diagnostics/alerts for VMSS or agent logs |
| Azure Best Practices / Docs | New Azure resource unfamiliar or policy review |
| Code Scanning / Security | Security hardening phase |

## Deferred / Excluded For Now
| Category | Reason |
|----------|--------|
| Azure Containers / AKS / ACR | Not using containers or Kubernetes |
| Databases (SQL, Cosmos, PostgreSQL, MySQL) | No data plane scope |
| Storage Management | No blobs/queues/tables required yet |
| Terraform Tools | Using Bicep only |
| Architecture Design / Load Testing | Out of MVP scope |
| Azure DevOps Boards/Test/Wiki | Using GitHub + only self-hosted agents need infra |
| Discussions / Gists / Search | Not required for infra automation |
| Marketplace / API Center / Bicep Experimental | No current dependency |
| Specialized Services (Grafana, Kusto, AI Search, Redis) | Not in design |

## Activation Policy
1. Deny-by-default: If a task can be completed with core set, do not activate new tools.
2. One-shot justification required in commit/PR description when adding a conditional tool.
3. Remove (deactivate) conditional tools after task completion.
4. Reuse previously fetched context; avoid duplicate search/doc requests within same PR.

## Operational Guidelines
- Batch file reads before edits.
- Single edit per file per logical change.
- Prefer outputs already produced over re-querying Azure.
- Use parameterization instead of discovery where names are deterministic.
- Add new secrets only via Key Vault tool category—never embed in parameter JSON.

## Review Checklist (Add to PR Template)
- [ ] Only core tool categories used or justified
- [ ] No secrets in repo
- [ ] Region fallback logic intact
- [ ] Image version naming semantic (YYYY.MM.DD.N)
- [ ] VMSS updated via pipeline, not manual console

## Future Hooks (Optional)
- Introduce Monitoring tools when enabling diagnostics settings.
- Introduce Security tools before production launch.

---
Maintainer: Update this allow list if architectural scope expands (containers, data, observability pipeline, etc.).

## Related Files
- `.vscode/copilot-tools.json` – machine-readable minimal tool set consumed by automation (editor/discovery friendly).
- `docs/tool-allowlist.json` – extended allow/exclude catalog.
