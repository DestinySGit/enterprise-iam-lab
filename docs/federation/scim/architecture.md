# SCIM Provisioning Architecture

Automated user and group provisioning from **Microsoft Entra ID** to the **Northwind Employee Portal** via SCIM 2.0.

## System Context

```mermaid
flowchart TB
  subgraph entra [Entra ID]
    Users[User Store]
    Groups[Security Groups]
    ProvJob[Provisioning Job]
  end

  subgraph portal [Northwind Portal]
    SCIM[SCIM Endpoint]
    AppUsers[Application Users]
  end

  subgraph jml [Lifecycle Automation]
    Joiner[Invoke-Joiner]
    Leaver[Invoke-Leaver]
  end

  Joiner --> Users
  Leaver --> Users
  Users --> ProvJob
  Groups --> ProvJob
  ProvJob -->|SCIM POST/PATCH/DELETE| SCIM
  SCIM --> AppUsers
```

## Provisioning Flow

### Create (Joiner)

```text
New user created in Entra (Invoke-Joiner or manual)
        ↓
Assigned to SG-DEPT-*, SG-ROLE-*, SG-APP-NorthwindPortal
        ↓
Entra provisioning job detects new assignment scope
        ↓
SCIM POST /Users → account created in Portal
```

### Update (Mover)

```text
User department/title/manager updated (Invoke-Mover)
        ↓
SCIM PATCH /Users/{id} → attributes updated in Portal
```

### Deprovision (Leaver)

```text
User disabled in Entra (Invoke-Leaver)
        ↓
SCIM PATCH /Users/{id} active=false OR DELETE
        ↓
Access removed in Portal
```

## Configuration

Attribute mapping spec: [scim-portal.mapping.json](../../../automation/config/scim-portal.mapping.json)

JML automation that drives provisioning events: [JML runbook](../../jml/joiner-mover-leaver.md).
