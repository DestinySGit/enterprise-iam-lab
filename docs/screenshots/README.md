# Screenshot Guide



Captured Entra admin center screenshots.



## Capture Method



Use Snipping Tool or ShareX in [entra.microsoft.com](https://entra.microsoft.com). Crop or blur tenant GUIDs, client IDs, object IDs, and admin UPNs before committing.



On a Free-tier tenant, some blades (custom CA, access review campaigns, live SAML/OIDC sign-in, SCIM) are not available in the portal. Those portfolio images are committed as design-spec or procedure captures alongside live portal shots.



## Required Screenshots



### Authentication & Conditional Access



| File name | Entra blade | Purpose |

|-----------|-------------|---------|

| `ca-policies-list.png` | Protection > Conditional Access | Show naming convention |

| `ca-mfa-all-users.png` | CA-002 policy detail | MFA grant controls |

| `mfa-registration-methods.png` | Protection > Authentication methods | MFA methods enabled |

| `group-assignments.png` | Groups > SG-DEPT-Engineering > Members | Group-based access |

| `access-review-campaign.png` | Identity Governance > Access reviews | Quarterly campaign |



### SAML Federation (Salesforce CRM)



| File name | Entra blade | Purpose |

|-----------|-------------|---------|

| `saml-salesforce-config.png` | Enterprise apps > Salesforce CRM > Single sign-on | SAML basic configuration |

| `saml-claims-mapping.png` | Enterprise apps > Attributes & Claims | Group and user attribute claims |

| `saml-login-flow.png` | Sign-in logs or SAML test | Successful SSO event |



### OIDC & OAuth (Northwind Portal)



| File name | Entra blade | Purpose |

|-----------|-------------|---------|

| `oidc-app-registration.png` | App registrations > Authentication | Redirect URIs and tokens |

| `oidc-token-configuration.png` | App registrations > Token configuration | Optional claims and groups |

| `oidc-login-success.png` | Sign-in logs | Successful OIDC authentication |



### SCIM Provisioning (Northwind Portal)



| File name | Entra blade | Purpose |

|-----------|-------------|---------|

| `scim-provisioning.png` | Enterprise apps > Provisioning | Provisioning job and mappings |

| `scim-deprovisioning.png` | Provisioning logs | User disable/delete event |




## Portfolio Files



```

docs/screenshots/

├── ca-policies-list.png

├── ca-mfa-all-users.png

├── mfa-registration-methods.png

├── group-assignments.png

├── access-review-campaign.png

├── saml-salesforce-config.png

├── saml-claims-mapping.png

├── saml-login-flow.png

├── oidc-app-registration.png

├── oidc-token-configuration.png

├── oidc-login-success.png

├── scim-provisioning.png

└── scim-deprovisioning.png

```

For architecture context, see [SAML](../federation/saml/architecture.md), [OIDC](../federation/oidc/architecture.md), and [SCIM](../federation/scim/architecture.md) docs plus [Entra ID Free limitations](../setup/entra-free-limitations.md).
