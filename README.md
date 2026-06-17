# Enterprise IAM Lab

## Why I Built This

I built this lab because I wanted something I could showcase my IAM knowledge. I modeled a mid-sized org (**Northwind Collaborative**, 50 synthetic users) and wired up the parts of Entra that matter in enterprise identity: group-based RBAC, SAML federation, OIDC/OAuth, SCIM provisioning design, JML automation via Microsoft Graph, and access governance procedures I'd actually run in production.

The hardest part was doing it on an **Entra ID Free** tenant without P1/P2. I couldn't deploy custom Conditional Access or access review campaigns in the portal, so those exist here as specs and runbooks. Federation was similarly split—SAML config is real on the Entra side, but full SSO loops need external apps I didn't have hosted.

If I rebuilt this, I'd grab a P1/P2 trial so CA and sign-in activity reports are live, and I'd stand up a minimal Northwind Portal host so OIDC and SCIM aren't only documented. More detail: [Lessons Learned](docs/setup/lessons-learned.md).

This repo demonstrates IAM engineering through architecture documentation, PowerShell automation, and governance runbooks for **Northwind Collaborative**—RBAC, identity federation (SAML, OIDC, OAuth), SCIM provisioning, MFA/Conditional Access design, Joiner-Mover-Leaver automation, Microsoft Graph certificate authentication, access governance, inactive-user reporting, and break-glass controls.

## Tenant Model
This lab runs on an **Entra ID Free** tenant (Azure-linked directory without M365 E5/P2 commerce). That is intentional for this build:

| Layer | Live in tenant | Documented in repo |
|-------|----------------|-------------------|
| Users, groups, RBAC, JML scripts | Yes | Yes |
| MFA (Authenticator) + Security defaults | Yes | Yes |
| SAML federation (Salesforce CRM) | Yes (gallery app) | Yes — [saml-salesforce.spec.json](automation/config/saml-salesforce.spec.json) |
| OIDC/OAuth (Northwind Portal) | Partial | Yes — [oidc-portal.spec.json](automation/config/oidc-portal.spec.json) |
| SCIM provisioning (Portal) | Partial | Yes — [scim-portal.mapping.json](automation/config/scim-portal.mapping.json) |
| Custom Conditional Access policies | No (requires P1+) | Yes — [ca-policies.spec.json](automation/config/ca-policies.spec.json) |
| Access review campaigns | No (requires P2) | Yes — runbooks + `Get-InactiveUsers.ps1` |

> *Production deployment of CA and access governance requires Entra ID P1/P2 licensing. Federation protocol configuration is documented for portfolio review; live SSO requires Salesforce Developer Edition or Portal host. See [Entra ID Free limitations](docs/setup/entra-free-limitations.md) for the full live vs documented matrix.*

## 15-Minute Reviewer Path

1. **[Architecture](docs/architecture/overview.md)** — identity model, federation flows, admin design
2. **[RBAC Matrix](docs/rbac/rbac-matrix.md)** — role → group → app → directory role mapping
3. **[SAML Federation](docs/federation/saml/architecture.md)** — Entra ID → Salesforce SSO
4. **[OIDC & OAuth](docs/federation/oidc/architecture.md)** — Northwind Portal token flow
5. **[SCIM Provisioning](docs/federation/scim/architecture.md)** — automated lifecycle sync
6. **[JML Runbook](docs/jml/joiner-mover-leaver.md)** — Joiner/Mover/Leaver automation
7. **[Conditional Access](docs/architecture/conditional-access.md)** — MFA policies and rollout sequence
8. **[Access Governance](docs/access-governance/quarterly-review.md)** — quarterly certification procedure
9. **[Application Onboarding](docs/application-onboarding/runbook.md)** — enterprise app integration runbook
10. **[Automation scripts](automation/scripts/)** — Graph API PowerShell implementation

## What This Demonstrates

| Capability | Evidence |
|------------|----------|
| Entra ID administration | 50-user org, department/manager hierarchy |
| RBAC & least privilege | Group-based access, break-glass model, entitlement matrix |
| SAML federation | Entra → Salesforce SSO, security-group claims |
| OIDC & OAuth | Authorization code flow, tokens, scopes, Portal app roles |
| SCIM provisioning | Attribute mapping, Joiner/Leaver sync to Portal |
| MFA & authentication baseline | Authenticator + Security defaults (Entra Free) |
| Conditional Access (design) | 4 policy specs + rollout docs (P1+ for portal deploy) |
| Joiner/Mover/Leaver | `Invoke-Joiner`, `Invoke-Mover`, `Invoke-Leaver` scripts |
| Access governance | Inactive-user script + quarterly review + group owners |
| Application onboarding | Runbook for SAML/OIDC/SCIM integration |
| Automation | Microsoft Graph + certificate auth app registration |
| Portfolio evidence | [Screenshots](docs/screenshots/) — redacted tenant captures + design-spec mockups for Free-tier-restricted features |

## Quick Start (Operator)

### Prerequisites

- Microsoft Entra ID tenant (Entra Free is sufficient for the core lab)
- PowerShell 7+
- Entra app registration with certificate auth
- MFA registered on admin account

### Setup

```powershell
# 1. Configure environment
cd automation
Copy-Item .env.example .env
# Edit .env with your tenant values

# 2. Install modules and connect
cd scripts
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users,
  Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns,
  Microsoft.Graph.Identity.Governance -Scope CurrentUser
.\Connect-LabTenant.ps1

# 3. Bootstrap identity
.\Import-LabGroups.ps1
.\Import-LabUsers.ps1 -Password 'ChangeMe!2026Lab'
```

4. Enable **Security defaults**: Entra admin center → Properties → Manage security defaults → **Enabled**

Full guide: [docs/setup/tenant-setup.md](docs/setup/tenant-setup.md)

## Repository Structure

```text
enterprise-iam-lab/
├── README.md
├── docs/
│   ├── architecture/          # Diagrams, CA/MFA design
│   ├── federation/            # SAML, OIDC, OAuth, SCIM
│   ├── application-onboarding/
│   ├── access-governance/
│   ├── rbac/
│   ├── jml/
│   ├── setup/
│   └── screenshots/
├── automation/
│   ├── config/                # Seed JSON, federation specs
│   └── scripts/               # PowerShell automation
└── reports/samples/
```

## Key Scripts

| Script | Purpose |
|--------|---------|
| [Connect-LabTenant.ps1](automation/scripts/Connect-LabTenant.ps1) | Certificate-based Graph connection |
| [Import-LabGroups.ps1](automation/scripts/Import-LabGroups.ps1) | Create security groups |
| [Import-LabUsers.ps1](automation/scripts/Import-LabUsers.ps1) | Seed 50 users + memberships |
| [Configure-LabApps.ps1](automation/scripts/Configure-LabApps.ps1) | Enterprise app onboarding |
| [Invoke-Joiner.ps1](automation/scripts/Invoke-Joiner.ps1) | New hire provisioning |
| [Invoke-Mover.ps1](automation/scripts/Invoke-Mover.ps1) | Department/role transfer |
| [Invoke-Leaver.ps1](automation/scripts/Invoke-Leaver.ps1) | Termination workflow |
| [Verify-LabJml.ps1](automation/scripts/Verify-LabJml.ps1) | JML + break-glass safeguard validation |
| [Verify-LabAuthControls.ps1](automation/scripts/Verify-LabAuthControls.ps1) | Security defaults + CA validation |
| [Verify-LabAccessGovernance.ps1](automation/scripts/Verify-LabAccessGovernance.ps1) | Governance scope validation |
| [Export-RbacMatrix.ps1](automation/scripts/Export-RbacMatrix.ps1) | RBAC CSV export |
| [Get-InactiveUsers.ps1](automation/scripts/Get-InactiveUsers.ps1) | 90-day inactivity report |
| [Export-CaPolicyChecklist.ps1](automation/scripts/Export-CaPolicyChecklist.ps1) | CA policy rollout checklist CSV |
| [Configure-LabOidcApps.ps1](automation/scripts/Configure-LabOidcApps.ps1) | OIDC redirect URIs, claims, API scope |

Federation validation: `Verify-LabFederation.ps1` (SAML + OIDC). SAML is configured in the Entra portal on the gallery **Salesforce CRM** app.

## Documentation Index

- [Lessons Learned](docs/setup/lessons-learned.md)
- [Architecture Overview](docs/architecture/overview.md)
- [SAML Federation](docs/federation/saml/architecture.md)
- [OIDC Integration](docs/federation/oidc/architecture.md)
- [OAuth Authorization](docs/federation/oauth/authorization.md)
- [SCIM Provisioning](docs/federation/scim/architecture.md)
- [Application Onboarding](docs/application-onboarding/runbook.md)
- [Entitlement Matrix](docs/access-governance/entitlement-matrix.md)
- [Quarterly Access Reviews](docs/access-governance/quarterly-review.md)
- [RBAC Matrix](docs/rbac/rbac-matrix.md)
- [JML Runbook](docs/jml/joiner-mover-leaver.md)
- [Conditional Access & MFA](docs/architecture/conditional-access.md)
- [Tenant Setup](docs/setup/tenant-setup.md)
- [Entra ID Free Limitations](docs/setup/entra-free-limitations.md)
- [CA Rollout Runbook](docs/setup/ca-rollout-runbook.md)
- [Portfolio Screenshots](docs/screenshots/)
- [Screenshot Guide](docs/screenshots/README.md)

## License

MIT — synthetic data and documentation only. Microsoft Entra ID is a Microsoft product; this repo is an independent lab project.
