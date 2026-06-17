# Entra ID Free — Lab Limitations

This document describes what **Microsoft Entra ID Free** can and cannot do in the Enterprise IAM Lab. The lab intentionally runs on a Free-tier tenant when P1/P2 licensing is unavailable.

## Tenant Context

| Item | This lab |
|------|----------|
| Directory type | Azure-linked Entra ID tenant |
| Licensing | Entra ID **Free** (no P1/P2 commerce on operator tenant) |
| Fictional org | Northwind Collaborative — 50 synthetic users |
| Auth baseline | Security defaults + Microsoft Authenticator |
| Design artifacts | CA specs, governance runbooks, federation mappings, screenshots |

> **Reviewer note:** Many enterprise IAM patterns (Conditional Access, access review campaigns, PIM) are **fully documented and automated in this repo** but require **Entra ID P1 or P2** to deploy in the Entra admin center. That gap is deliberate and called out below.

## Summary Matrix

| Capability | Live on Free tenant | Documented in repo | Minimum license to deploy in portal |
|------------|--------------------|--------------------|-------------------------------------|
| Users, groups, departments | Yes | Yes | Free |
| Security defaults (MFA baseline) | Yes | Yes | Free |
| Microsoft Authenticator | Yes | Yes | Free |
| RBAC via security groups | Yes | Yes | Free |
| Directory role assignment (direct) | Yes | Yes | Free |
| App registration (OIDC/OAuth) | Yes | Yes | Free |
| SAML gallery app (Salesforce CRM) | Yes (Entra-side) | Yes | Free + Salesforce org for full SSO |
| PowerShell / Graph automation | Yes | Yes | Free (with app permissions) |
| Custom Conditional Access policies | **No** | Yes — [ca-policies.spec.json](../../automation/config/ca-policies.spec.json) | **P1+** |
| CA report-only → enforce rollout | **No** | Yes — [ca-rollout-runbook.md](./ca-rollout-runbook.md) | **P1+** |
| Sign-in activity (`SignInActivity`) | **No** | Yes — proxy fallback in scripts | **P1+** |
| Entra access review campaigns | **No** | Yes — [quarterly-review.md](../access-governance/quarterly-review.md) | **P2** |
| Privileged Identity Management (PIM) | **No** | Yes — [lessons-learned.md](./lessons-learned.md) | **P2** |
| Group-based app role assignment (portal) | **Limited** | Yes — Graph automation | Free (via Graph); portal UI restricted |
| SCIM provisioning to live app | **Partial** | Yes — [scim-portal.mapping.json](../../automation/config/scim-portal.mapping.json) | Free + hosted SCIM endpoint |
| OIDC login to live Portal SPA | **Partial** | Yes — [oidc-portal.spec.json](../../automation/config/oidc-portal.spec.json) | Free + hosted application |

## Authentication and Conditional Access

### What works on Free

- **Security defaults** enforce MFA registration for administrators and block legacy authentication at a baseline level.
- **Microsoft Authenticator** can be enabled under **Protection → Authentication methods**.
- Break-glass exclusion groups (`SG-EXCLUDE-BreakGlass`) and lab verification via `Verify-LabAuthControls.ps1` work against live tenant data.

### What does not work on Free

- **Custom Conditional Access policies** cannot be created or enforced in the portal. Policies such as `CA-001-Block-Legacy-Auth` through `CA-004-Block-Unknown-Locations-Admins` exist as **design specifications** only.
- **Report-only CA rollout**, per-app CA scoping (Salesforce, Northwind Portal), and **sign-in log CA evaluation** for custom policies require P1+.
- Security defaults and custom CA policies **conflict** — disable Security defaults before deploying custom CA in a P1+ tenant.

### Lab workaround

| Deliverable | Location |
|-------------|----------|
| Policy definitions | `automation/config/ca-policies.spec.json` |
| Rollout checklist CSV | `Export-CaPolicyChecklist.ps1` |
| Operator paths (Free vs P1+) | [ca-rollout-runbook.md](./ca-rollout-runbook.md) |
| Design-spec screenshots | `docs/screenshots/ca-*.png` (committed portfolio captures) |

## Identity Federation (SAML, OIDC, SCIM)

### SAML (Salesforce CRM)

| Aspect | Free-tier status |
|--------|------------------|
| Entra gallery app configuration | **Live** — SSO blade, claims, group assignment |
| Full end-to-end SSO | **Requires** Salesforce Developer Edition or production org |
| Portfolio evidence | Spec + screenshots + `Verify-LabFederation.ps1` |

### OIDC / OAuth (Northwind Employee Portal)

| Aspect | Free-tier status |
|--------|------------------|
| App registration, redirect URIs, scopes | **Live** (or automatable via `Configure-LabOidcApps.ps1`) |
| Group → app role assignment | **Graph automation** — Entra Free portal may block group assignment UI for some app types |
| Admin consent for exposed API | May require manual grant under **Enterprise applications → Permissions** |
| Live SPA login flow | **Requires** hosted Portal application at redirect URI |

### SCIM provisioning

| Aspect | Free-tier status |
|--------|------------------|
| Attribute mapping design | **Documented** in `scim-portal.mapping.json` |
| Entra provisioning job | **Requires** reachable SCIM endpoint (no live Portal host in base lab) |
| Joiner/Leaver lifecycle | **Live** in Entra via `Invoke-Joiner.ps1` / `Invoke-Leaver.ps1`; SCIM sync is simulated in docs/screenshots |

## Access Governance

### What works on Free

- **Group owners** assigned via `Set-LabGroupOwners.ps1` for department review scope.
- **RBAC matrix export** via `Export-RbacMatrix.ps1`.
- **Quarterly procedure** documented in [quarterly-review.md](../access-governance/quarterly-review.md).
- **Inactive user report** via `Get-InactiveUsers.ps1` using a **password-change proxy** when `SignInActivity` is unavailable.

### What does not work on Free

- **Entra access review campaigns** (Identity Governance → Access reviews) require **Entra ID P2**.
- Campaign result exports from the portal are not available; sample format is in `reports/samples/access-certification-sample.csv`.
- True **90-day sign-in inactivity** based on `lastSignInDateTime` requires P1/P2; Free tenants see `DataSource: PasswordChangeProxy` in report output.

### Lab workaround (hybrid governance)

1. Department group owners review membership on a quarterly cadence (procedure doc).
2. `Get-InactiveUsers.ps1` surfaces stale accounts for operator action.
3. `Verify-LabAccessGovernance.ps1` validates scope, owners, and report scripts.
4. `access-review-campaign.png` documents the **procedure + automation** model, not a live P2 campaign.

## Privileged Access (PIM)

**Privileged Identity Management** is not available on Entra ID Free. This lab uses:

- A standing **break-glass** Global Administrator (`adm-breakglass`) in `SG-EXCLUDE-BreakGlass`
- **Eligible vs Active** role assignment patterns I'd deploy with P2 — see [lessons-learned.md](./lessons-learned.md)

PIM activation flows, audit logs, and eligible assignment screenshots require **Entra ID P2**.

## Automation and Graph API

| Script / API | Free-tier behavior |
|--------------|-------------------|
| `Connect-LabTenant.ps1` | Works — certificate auth app registration |
| `Import-LabUsers.ps1` / `Import-LabGroups.ps1` | Works |
| `Configure-LabApps.ps1` | Works — app role assignment via Graph |
| `Get-InactiveUsers.ps1` | Works — falls back to `lastPasswordChangeDateTime` |
| `Export-RbacMatrix.ps1` | Works — includes live member counts from Graph |
| `Get-MgIdentityGovernanceAccessReviewDefinition` | **Fails or 403** without P2 — expected; documented only |

## Portfolio Screenshots

Screenshots in `docs/screenshots/` are labeled by capture type:

| Capture type | Meaning |
|--------------|---------|
| **Live portal capture** | Snipped from Entra admin center (e.g. groups, MFA, SAML/OIDC config) |
| **Design spec** | Committed images for blades requiring P1/P2 or external apps (CA, SCIM flows) |
| **Procedure** | Documents governance workflow when portal feature needs P2 |

Identifiers (tenant GUIDs, client IDs, object IDs) are redacted per [screenshot guide](../screenshots/README.md).

## Upgrade Paths

To move from documentation-only to live portal deployment:

| Goal | License | Starting point |
|------|---------|----------------|
| Custom CA policies | Entra ID **P1** | [ca-rollout-runbook.md](./ca-rollout-runbook.md) Path B |
| Sign-in activity reports | Entra ID **P1** | Re-run `Get-InactiveUsers.ps1` (auto-detects `SignInActivity`) |
| Access review campaigns | Entra ID **P2** | [quarterly-review.md](../access-governance/quarterly-review.md) |
| PIM eligible assignments | Entra ID **P2** | [lessons-learned.md](./lessons-learned.md) |


## What Reviewers Should Expect

1. **Architecture and automation are production-style** — group-based RBAC, federation specs, JML scripts, and governance procedures reflect how IAM teams design and operate Entra environments.
2. **Some portal blades are intentionally simulated** — CA policy list, access review campaign scope, and partial federation flows are portfolio captures when P1/P2 or external apps are not wired.
3. **Honesty over completeness** — the [README](../../README.md) tenant model table and this document distinguish live vs documented capabilities.

## Related Documents

- [Lessons Learned](./lessons-learned.md)
- [Tenant Setup](./tenant-setup.md)
- [Conditional Access Rollout](./ca-rollout-runbook.md)
- [Architecture Overview](../architecture/overview.md)
- [Conditional Access Design](../architecture/conditional-access.md)
- [Quarterly Access Reviews](../access-governance/quarterly-review.md)
- [Screenshot Guide](../screenshots/README.md)
