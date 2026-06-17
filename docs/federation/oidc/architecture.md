# OIDC Architecture — Northwind Employee Portal

OpenID Connect authentication from **Microsoft Entra ID** to the **Northwind Employee Portal** using the authorization code flow.

## System Context

```mermaid
flowchart LR
  User[Employee]
  Portal[Northwind Portal RP]
  Entra[Entra ID IdP]
  CA[Conditional Access]
  Groups[SG-APP-NorthwindPortal]

  User -->|1 Sign in| Portal
  Portal -->|2 Authorize request| Entra
  Entra --> CA
  CA -->|3 MFA if required| Entra
  Groups -->|4 App role claims| Entra
  Entra -->|5 Auth code| Portal
  Portal -->|6 Token exchange| Entra
  Entra -->|7 ID + access tokens| Portal
  Portal -->|8 Access granted| User
```

## Components

| Component | Role |
|-----------|------|
| Microsoft Entra ID | OpenID Provider — authenticates users, issues tokens |
| Northwind Employee Portal | Relying Party — validates tokens, enforces app roles |
| `SG-APP-NorthwindPortal` | Group for `Portal.User` role assignment |
| `SG-ROLE-IT-Administrator` | Group for `Portal.Admin` role assignment |

## Configuration Spec

Lab configuration: [oidc-portal.spec.json](../../../automation/config/oidc-portal.spec.json)

Apply to tenant: `Configure-LabOidcApps.ps1` (after `Configure-LabApps.ps1`)

See also [token flow](./token-flow.md), [claims](./claims.md), and [OAuth authorization](../oauth/authorization.md).
