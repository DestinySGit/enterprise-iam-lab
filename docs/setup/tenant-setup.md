# Tenant Setup Guide

Configure the Microsoft Entra ID lab tenant for **Northwind Collaborative**.

## Prerequisites

- Microsoft 365 Developer Program account ([sign up](https://developer.microsoft.com/microsoft-365/dev-program))
- PowerShell 7+
- Windows certificate store (for app registration certificate auth)

## Step 1: Register Developer Tenant

1. Join the Microsoft 365 Developer Program and create a new instant sandbox tenant.
2. Record your tenant name (e.g. `northwindcollab.onmicrosoft.com`).
3. Note the **tenant renewal date** in your personal calendar (renew before expiry).
4. Confirm your tenant has the licenses you need for your lab path (Entra Free is sufficient for users, groups, RBAC, and Security defaults).

## Step 2: Initial Admin Hardening

1. Sign in to [Entra admin center](https://entra.microsoft.com) with your **`@tenant.onmicrosoft.com` admin** (not your personal Microsoft account).
2. **Protection → Authentication methods** — enable Microsoft Authenticator.
3. Register MFA at [mysignins.microsoft.com/security-info](https://mysignins.microsoft.com/security-info) — **works without P2**.
4. Create break-glass via `Import-LabUsers.ps1` or manually (`adm-breakglass@<tenant>`).
5. After group import, add break-glass to `SG-EXCLUDE-BreakGlass`.

## Step 3: App Registration

1. **Entra ID > Applications > App registrations > New registration**
   - Name: `Northwind-Lab-Automation`
   - Supported account types: Single tenant
   - Redirect URI: none (daemon app)
2. Note the **Application (client) ID** and **Directory (tenant) ID**.
3. **Certificates & secrets > Certificates > Upload certificate**
   ```powershell
   $cert = New-SelfSignedCertificate -Subject "CN=NorthwindLabAutomation" `
     -CertStoreLocation "Cert:\CurrentUser\My" `
     -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 `
     -KeyAlgorithm RSA -HashAlgorithm SHA256 -NotAfter (Get-Date).AddYears(2)
   $cert.Thumbprint
   ```
4. **API permissions > Application permissions** (grant admin consent):
   - `User.ReadWrite.All`
   - `Group.ReadWrite.All`
   - `Directory.Read.All`
   - `AuditLog.Read.All`
   - `Policy.Read.All`
5. Click **Grant admin consent for [tenant]**.

## Step 4: Configure Local Environment

```powershell
cd automation
Copy-Item .env.example .env
# Edit .env with TENANT_ID, CLIENT_ID, CERT_THUMBPRINT, DOMAIN
```

## Step 5: Install PowerShell Modules

```powershell
Install-Module Microsoft.Graph.Authentication, Microsoft.Graph.Users, `
  Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns, `
  Microsoft.Graph.Identity.Governance -Scope CurrentUser -Force
```

## Step 6: Bootstrap Identity

```powershell
cd automation/scripts
.\Connect-LabTenant.ps1
.\Import-LabGroups.ps1
.\Import-LabUsers.ps1 -Password 'ChangeMe!2026Lab'
```

## Step 7: Group-Based Licensing

1. **Entra ID > Licenses > All products** — confirm Microsoft 365 E3/E5 trial available.
2. **Entra ID > Groups > SG-LIC-M365-E3 > Licenses** — assign Microsoft 365 E3.
3. Verify a test user receives license after group membership.

## Step 8: Enterprise Applications

Register per [apps.definition.json](../../automation/config/apps.definition.json):

1. **Northwind Employee Portal** — App registration + expose app roles; assign groups.
2. **Microsoft 365** — Assign `SG-APP-Microsoft365` to Office 365 Enterprise Application.

Salesforce is added from the Entra application gallery — see [SAML architecture](../federation/saml/architecture.md).

## Step 9: Conditional Access

Follow [ca-policies.spec.json](../../automation/config/ca-policies.spec.json) and [conditional-access.md](../architecture/conditional-access.md).

## Step 10: Directory Role Assignments

| Role | Assignee |
|------|----------|
| Global Administrator | `adm-breakglass` only |
| User Administrator | `SG-ROLE-HR-Administrator` |
| Privileged Role Administrator | `SG-ROLE-IT-Administrator` |

## Verification Checklist

- [ ] Graph connection succeeds via certificate
- [ ] 50 users visible in Entra ID
- [ ] Department groups populated
- [ ] Break-glass excluded from CA policies
- [ ] MFA registered on admin accounts
- [ ] `.env` not committed to git

## Renewal

Before Developer Program expiry:

1. Renew at [developer.microsoft.com](https://developer.microsoft.com/microsoft-365/dev-program)
2. Re-run `Import-LabGroups.ps1` and `Import-LabUsers.ps1` (idempotent) if tenant was reset
