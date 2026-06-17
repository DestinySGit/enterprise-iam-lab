# Automation

PowerShell scripts for provisioning, federating, and governing the Northwind Collaborative lab tenant via Microsoft Graph.

## Prerequisites

1. Complete [tenant setup](../docs/setup/tenant-setup.md)
2. Copy `.env.example` to `.env` in this directory
3. Install Microsoft Graph PowerShell modules (see Connect-LabTenant.ps1)

## Execution Order

```powershell
cd automation/scripts

# 1. Connect
.\Connect-LabTenant.ps1

# 2. Foundation (if Connect reports missing User.ReadWrite.All)
.\Fix-LabAppPermissions.ps1   # interactive Global Admin — one-time
.\Connect-LabTenant.ps1       # re-verify scopes
.\Import-LabGroups.ps1
.\Import-LabUsers.ps1 -Password 'ChangeMe!2026Lab'
.\Verify-LabIdentity.ps1

# 3. RBAC and enterprise apps (if Connect reports missing Application.* scopes)
.\Fix-LabAppPermissions.ps1   # adds Application + RoleManagement permissions
.\Connect-LabTenant.ps1
.\Configure-LabApps.ps1
.\Verify-LabRbac.ps1

# 4. SAML federation
.\Verify-LabFederation.ps1 -Protocol SAML

# 5. OIDC/OAuth
.\Configure-LabOidcApps.ps1
.\Verify-LabFederation.ps1 -Protocol OIDC

# 6. Auth controls
.\Verify-LabAuthControls.ps1
.\Export-CaPolicyChecklist.ps1

# 7. JML automation + SCIM
.\Verify-LabJml.ps1
# Full lifecycle: Invoke-Joiner.ps1 → Invoke-Mover.ps1 → Invoke-Leaver.ps1

# 8. Governance reports
.\Set-LabGroupOwners.ps1
.\Verify-LabAccessGovernance.ps1
.\Export-RbacMatrix.ps1
.\Get-InactiveUsers.ps1 -InactiveDays 90
```

## Config Files

| File | Purpose |
|------|---------|
| [config/users.seed.json](config/users.seed.json) | 50 synthetic users |
| [config/groups.definition.json](config/groups.definition.json) | Security group definitions |
| [config/apps.definition.json](config/apps.definition.json) | Enterprise app assignments (protocol, SSO mode) |
| [config/saml-salesforce.spec.json](config/saml-salesforce.spec.json) | SAML SSO settings and claims |
| [config/oidc-portal.spec.json](config/oidc-portal.spec.json) | OIDC redirect URIs, scopes, app roles |
| [config/scim-portal.mapping.json](config/scim-portal.mapping.json) | SCIM attribute mapping |
| [config/ca-policies.spec.json](config/ca-policies.spec.json) | Conditional Access specs |

## Federation Specs

SAML, OIDC, and SCIM configuration is defined in spec JSON files under `config/`. Portal configuration steps are documented in:

- [SAML Federation](../docs/federation/saml/architecture.md)
- [OIDC & OAuth](../docs/federation/oidc/architecture.md)
- [SCIM Provisioning](../docs/federation/scim/architecture.md)

## Auth Control Scripts

- `Verify-LabAuthControls.ps1` — Security defaults, break-glass exclusions, CA policy validation
- `Export-CaPolicyChecklist.ps1` — portal rollout CSV from CA spec

See [CA rollout runbook](../docs/setup/ca-rollout-runbook.md).

## JML Scripts

- `Invoke-Joiner.ps1` — on-demand new hire (triggers SCIM create when configured)
- `Invoke-Mover.ps1` — department/role transfer
- `Invoke-Leaver.ps1` — termination (`-RemoveLicenses` to reclaim SKUs; triggers SCIM deprovision)
- `Verify-LabJml.ps1` — script presence, group resolution rules, break-glass refusal

See [JML runbook](../docs/jml/joiner-mover-leaver.md).

## Governance Scripts

- `Set-LabGroupOwners.ps1` — assign owners on access review scope groups
- `Verify-LabAccessGovernance.ps1` — review scope, group owners, report scripts
- `Get-InactiveUsers.ps1` — 90-day inactivity report (SignInActivity or Free-tier proxy)
- `Export-RbacMatrix.ps1` — pre-review RBAC baseline CSV

See [Quarterly Access Reviews](../docs/access-governance/quarterly-review.md) and [Entitlement Matrix](../docs/access-governance/entitlement-matrix.md).

## Application Onboarding

See [Application Onboarding Runbook](../docs/application-onboarding/runbook.md) for the full enterprise app integration procedure.
