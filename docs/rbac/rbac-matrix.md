# RBAC Matrix

Role-based access control for **Northwind Collaborative**. Group membership drives application and license assignment; Entra directory roles are assigned sparingly per least privilege.

## Role Tier → Group → Access

| Role Tier | Security Groups | Applications | Entra Directory Role |
|-----------|-----------------|--------------|----------------------|
| Employee | `SG-ROLE-Employee`, `SG-DEPT-*`, `SG-APP-M365`, `SG-APP-NorthwindPortal`, `SG-LIC-M365-E3` | M365, Employee Portal | — |
| Manager | `SG-ROLE-Manager` + Employee groups | Same as Employee | — |
| HR Administrator | `SG-ROLE-HR-Administrator`, `SG-DEPT-HR` | M365, Portal | User Administrator |
| IT Administrator | `SG-ROLE-IT-Administrator`, `SG-DEPT-IT` | M365, Portal (Admin) | Privileged Role Administrator |
| Break-glass | `SG-EXCLUDE-BreakGlass` | Emergency only | Global Administrator |

## Department → Application Access

| Department | M365 | Northwind Portal | Salesforce CRM |
|------------|------|------------------|----------------|
| HR | Yes | Yes | No |
| Finance | Yes | Yes | Yes |
| IT | Yes | Yes (Admin for IT Admins) | No |
| Engineering | Yes | Yes | No |
| Operations | Yes | Yes | Yes |

## Group Catalog

| Group | Type | Purpose |
|-------|------|---------|
| SG-DEPT-HR | Department | HR workforce |
| SG-DEPT-Finance | Department | Finance workforce |
| SG-DEPT-IT | Department | IT workforce |
| SG-DEPT-Engineering | Department | Engineering workforce |
| SG-DEPT-Operations | Department | Operations workforce |
| SG-ROLE-Employee | Role | Baseline employee entitlements |
| SG-ROLE-Manager | Role | Manager designation |
| SG-ROLE-IT-Administrator | Role | IT elevated access |
| SG-ROLE-HR-Administrator | Role | HR elevated access |
| SG-APP-Microsoft365 | Application | M365 access |
| SG-APP-NorthwindPortal | Application | Internal portal |
| SG-APP-Salesforce | Application | CRM (Finance, Operations) |
| SG-LIC-M365-E3 | License | Group-based E3 licensing |
| SG-EXCLUDE-BreakGlass | Exclusion | CA break-glass |

## Least Privilege Rules

1. No standing Global Administrator except break-glass.
2. Application access via groups — never direct user-to-app assignment except break-glass.
3. IT admins manage roles via Privileged Role Administrator, not Global Admin.
4. HR admins manage user profiles via User Administrator scoped to HR workflows.
5. License assignment via `SG-LIC-M365-E3` only — no direct license assignment in Joiner unless group licensing unavailable.

## Export

Generate a live matrix from your tenant:

```powershell
cd automation/scripts
.\Connect-LabTenant.ps1
.\Export-RbacMatrix.ps1
```

Output: `reports/rbac-matrix-<timestamp>.csv`

## Sample Export

See [reports/samples/rbac-matrix-sample.csv](../../reports/samples/rbac-matrix-sample.csv) for expected format.
