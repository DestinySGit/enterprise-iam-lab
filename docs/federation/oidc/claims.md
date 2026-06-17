# OIDC Claims — Northwind Employee Portal

Claims emitted in ID tokens and access tokens for the Northwind Portal OIDC integration.

## Standard OIDC Claims

| Claim | Source | Example |
|-------|--------|---------|
| `sub` | Entra object ID | Unique subject identifier |
| `name` | displayName | Jane Doe |
| `preferred_username` | UPN | jane.doe@northwindcollab.onmicrosoft.com |
| `email` | mail | jane.doe@northwindcollab.onmicrosoft.com |

## Group Claims

When group claims are enabled, the token includes group membership:

```json
{
  "groups": ["<group-object-id-for-SG-APP-NorthwindPortal>"]
}
```

For token size optimization in production, use `hasgroups` + Graph API or filter to security groups only. The lab emits group claims for demonstration.

## App Role Claims

App roles appear in the `roles` claim based on group-to-role assignment:

| Group | App Role | Claim value |
|-------|----------|-------------|
| `SG-APP-NorthwindPortal` | Portal.User | `Portal.User` |
| `SG-ROLE-IT-Administrator` | Portal.Admin | `Portal.Admin` |

## Portal Authorization Logic

```text
if roles contains "Portal.Admin" → admin dashboard
else if roles contains "Portal.User" → user dashboard
else → access denied
```

## Optional Claims Configuration

Configure in **App registrations > Token configuration**:

- Groups (Security groups)
- Email
- Preferred username

Spec reference: [oidc-portal.spec.json](../../../automation/config/oidc-portal.spec.json)
