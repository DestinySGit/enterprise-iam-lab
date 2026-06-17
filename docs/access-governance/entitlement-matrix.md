# Entitlement Matrix — Federated Applications

Application entitlements for Northwind Collaborative, extending the [RBAC matrix](../rbac/rbac-matrix.md) with federation protocol and app role detail.

## Federated Application Entitlements

| Application | Protocol | Security Group | App Role | Departments | Least Privilege |
|-------------|----------|----------------|----------|-------------|-----------------|
| Salesforce CRM | SAML | `SG-APP-Salesforce` | Security group claim | Finance, Operations | Gallery app; Entra Free uses Security groups claim |
| Northwind Portal | OIDC | `SG-APP-NorthwindPortal` | Portal.User | All employees | All staff |
| Northwind Portal | OIDC | `SG-ROLE-IT-Administrator` | Portal.Admin | IT | IT admins only |

## Directory Role Entitlements

| Directory Role | Assigned Via | Standing/Eligible |
|----------------|--------------|-------------------|
| Global Administrator | `adm-breakglass` | Standing (break-glass) |
| User Administrator | `SG-ROLE-HR-Administrator` | Standing |
| Privileged Role Administrator | `SG-ROLE-IT-Administrator` | Standing |

## First-Party Applications

| Application | Protocol | Security Group | Access |
|-------------|----------|----------------|--------|
| Microsoft 365 | First-party | `SG-APP-Microsoft365` | All employees |
| Microsoft 365 | First-party | `SG-LIC-M365-E3` | License assignment |

## Group-to-Claim Mapping

| Group | Salesforce SAML | Portal OIDC |
|-------|-----------------|-------------|
| `SG-APP-Salesforce` | groups claim | — |
| `SG-APP-NorthwindPortal` | — | Portal.User role |
| `SG-ROLE-IT-Administrator` | — | Portal.Admin role |

## SCIM Provisioning Scope

| Entra Event | Salesforce | Northwind Portal |
|-------------|------------|------------------|
| Joiner | Manual / out of scope | SCIM create |
| Mover | N/A | SCIM PATCH attributes |
| Leaver | Manual deassign | SCIM disable |

## Export

Generate live entitlement data:

```powershell
cd automation/scripts
.\Connect-LabTenant.ps1
.\Export-RbacMatrix.ps1
```

Compare with [reports/samples/rbac-matrix-sample.csv](../../reports/samples/rbac-matrix-sample.csv).

## Related Documents

- [RBAC Matrix](../rbac/rbac-matrix.md)
- [Quarterly Access Review](./quarterly-review.md)
- [Application Onboarding Runbook](../application-onboarding/runbook.md)
