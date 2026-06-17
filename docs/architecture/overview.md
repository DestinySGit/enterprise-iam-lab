# Architecture Overview

**Northwind Collaborative** is a Microsoft Entra ID organization demonstrating enterprise IAM patterns at mid-market scale (50 synthetic users), including SAML federation, OIDC/OAuth integration, and SCIM provisioning.

## System Context

```mermaid
flowchart TB
  subgraph users [Workforce]
    Emp[Employees]
    Mgr[Managers]
    Admins[IT and HR admins]
  end

  subgraph entra [Microsoft Entra ID]
    IdStore[User store]
    Groups[Security groups]
    CA[Conditional Access]
    Gov[Access reviews]
    Roles[Directory roles]
    SAML[SAML IdP]
    OIDC[OIDC provider]
    SCIM[SCIM provisioning]
  end

  subgraph apps [Applications]
    M365[Microsoft 365]
    Portal[Northwind Portal OIDC]
    SFDC[Salesforce CRM SAML]
  end

  subgraph automation [Lab automation]
    PS[PowerShell scripts]
    Graph[Microsoft Graph API]
  end

  Emp --> IdStore
  Mgr --> IdStore
  Admins --> Roles
  IdStore --> Groups
  Groups --> M365
  Groups --> Portal
  Groups --> SFDC
  SAML -->|SAML assertion| SFDC
  OIDC -->|OIDC tokens| Portal
  SCIM -->|provision| Portal
  CA --> IdStore
  Gov --> Groups
  PS --> Graph
  Graph --> IdStore
  Graph --> Groups
```

## Identity Model

| Layer | Mechanism | Examples |
|-------|-----------|----------|
| Department | Attribute + group | `department=Engineering`, `SG-DEPT-Engineering` |
| Role tier | Group | `SG-ROLE-Manager`, `SG-ROLE-IT-Administrator` |
| Application access | Group → app assignment | `SG-APP-Salesforce`, `SG-APP-NorthwindPortal` |
| Licensing | Group-based licensing | `SG-LIC-M365-E3` |
| Privileged access | Entra directory roles | Break-glass GA, IT = Privileged Role Admin |
| SAML federation | Entra IdP → Salesforce SP | Group claims in SAML assertion |
| OIDC federation | Entra IdP → Portal RP | App roles in token claims |
| SCIM provisioning | Entra → Portal | Automated create/disable on JML |

## Group Naming

| Pattern | Purpose |
|---------|---------|
| `SG-DEPT-*` | Department membership |
| `SG-ROLE-*` | Role-based access tiers |
| `SG-APP-*` | Application access |
| `SG-LIC-*` | License assignment |
| `SG-EXCLUDE-*` | CA policy exclusions |

## Authentication Flows

### Entra-Native (M365)

```mermaid
sequenceDiagram
  participant User
  participant App as Cloud app
  participant Entra as Entra ID
  participant CA as Conditional Access
  participant MFA as MFA provider

  User->>App: Sign in request
  App->>Entra: Redirect to Entra
  Entra->>CA: Evaluate policies
  alt Legacy auth
    CA-->>User: Block
  else MFA required
    CA->>MFA: Challenge
    MFA-->>Entra: Satisfied
    Entra-->>User: Issue token
  end
```

### SAML SSO (Salesforce CRM)

```mermaid
sequenceDiagram
  participant User
  participant SFDC as Salesforce
  participant Entra as Entra ID

  User->>SFDC: Sign in
  SFDC->>Entra: SAML AuthnRequest
  Entra->>Entra: Authenticate and MFA
  Entra->>SFDC: SAML assertion with claims
  SFDC->>User: Access granted
```

See [SAML Login Flow](../federation/saml/login-flow.md) for full detail.

### OIDC (Northwind Portal)

```mermaid
sequenceDiagram
  participant User
  participant Portal as Northwind Portal
  participant Entra as Entra ID

  User->>Portal: Sign in
  Portal->>Entra: OIDC authorize
  Entra->>Entra: Authenticate and MFA
  Entra->>Portal: Authorization code
  Portal->>Entra: Token exchange
  Entra->>Portal: ID and access tokens
  Portal->>User: Access granted
```

See [OIDC Token Flow](../federation/oidc/token-flow.md) for full detail.

## Admin Model

- **Break-glass** (`adm-breakglass`): Standing Global Administrator for emergencies only; member of `SG-EXCLUDE-BreakGlass`.
- **IT Administrators**: `SG-ROLE-IT-Administrator` → Privileged Role Administrator (not Global Admin).
- **HR Administrators**: `SG-ROLE-HR-Administrator` → User Administrator.
- **Automation**: App registration `Northwind-Lab-Automation` with certificate auth and application permissions.

## Data Sources

| Artifact | Location |
|----------|----------|
| User seed data | [users.seed.json](../../automation/config/users.seed.json) |
| Group definitions | [groups.definition.json](../../automation/config/groups.definition.json) |
| App assignments | [apps.definition.json](../../automation/config/apps.definition.json) |
| SAML spec | [saml-salesforce.spec.json](../../automation/config/saml-salesforce.spec.json) |
| OIDC spec | [oidc-portal.spec.json](../../automation/config/oidc-portal.spec.json) |
| SCIM mapping | [scim-portal.mapping.json](../../automation/config/scim-portal.mapping.json) |
| CA policy specs | [ca-policies.spec.json](../../automation/config/ca-policies.spec.json) |

## Related Documents

- [RBAC Matrix](../rbac/rbac-matrix.md)
- [Entitlement Matrix](../access-governance/entitlement-matrix.md)
- [SAML Federation](../federation/saml/architecture.md)
- [OIDC Integration](../federation/oidc/architecture.md)
- [SCIM Provisioning](../federation/scim/architecture.md)
- [Conditional Access](./conditional-access.md)
- [JML Runbook](../jml/joiner-mover-leaver.md)
- [Access Governance](../access-governance/quarterly-review.md)
- [Application Onboarding](../application-onboarding/runbook.md)
