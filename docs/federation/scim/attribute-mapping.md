# SCIM Attribute Mapping — Northwind Employee Portal

Entra ID to Northwind Portal SCIM attribute mappings for automated provisioning.

## User Attributes

| Entra ID Attribute | SCIM Attribute | Required | Notes |
|--------------------|----------------|----------|-------|
| `givenName` | `name.givenName` | Yes | First name |
| `surname` | `name.familyName` | Yes | Last name |
| `mail` | `emails[type eq "work"].value` | Yes | Primary email |
| `userPrincipalName` | `userName` | Yes | Login identifier |
| `department` | `urn:ietf:params:scim:schemas:extension:enterprise:2.0:User:department` | Yes | Department |
| `jobTitle` | `title` | Yes | Job title |
| `manager` | `manager.displayName` | No | Manager name reference |
| `accountEnabled` | `active` | Yes | `false` on leaver |

## Group Provisioning

When group sync is enabled:

| Entra Group | SCIM Group | Portal Effect |
|-------------|------------|---------------|
| `SG-APP-NorthwindPortal` | Portal Users | Base application access |
| `SG-ROLE-IT-Administrator` | Portal Admins | Admin role assignment |

## Portal Configuration Steps

1. **Entra ID > Enterprise applications > Northwind Employee Portal > Provisioning**
2. Set provisioning mode to **Automatic**
3. Enter SCIM endpoint URL and bearer token (from Portal)
4. Test connection
5. Configure attribute mappings per table above
6. Start provisioning

## Deprovisioning Behavior

| Entra Event | SCIM Action | Portal Result |
|-------------|-------------|---------------|
| User disabled | `active: false` | Login blocked |
| Removed from scope group | Unassign from group | App access removed |
| User deleted | DELETE /Users/{id} | Account removed |

Spec reference: [scim-portal.mapping.json](../../../automation/config/scim-portal.mapping.json)

## Lab Simulation

Without a live SCIM endpoint, document Entra provisioning configuration and attribute mappings. Capture portal screenshots of the provisioning blade and mapping table.
