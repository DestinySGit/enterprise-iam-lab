# OAuth 2.0 Authorization — Northwind Employee Portal

OAuth 2.0 authorization concepts demonstrated via the Northwind Portal OIDC client and exposed API scopes.

## Authorization Code Flow

The Portal uses OAuth 2.0 authorization code flow (combined with OIDC when `openid` scope is requested). See [OIDC Token Flow](../oidc/token-flow.md) for the full sequence.

## Scope Assignments

| Scope | Type | Consent | Purpose |
|-------|------|---------|---------|
| `openid` | OIDC | Auto | Authentication |
| `profile` | OIDC | Auto | Name and profile claims |
| `email` | OIDC | Auto | Email claim |
| `api://northwind-portal/access` | OAuth | Admin or user | Portal REST API access |

## Consent Process

### User Consent

Standard users consent to delegated permissions on first sign-in when the application requests user-delegated scopes.

### Admin Consent

IT administrators pre-consent organization-wide for the Portal application:

1. **Entra ID > Enterprise applications > Northwind Employee Portal > Permissions**
2. **Grant admin consent for {organization}**
3. Document consent timestamp in onboarding runbook

## API Authorization Example

Request with access token:

```http
GET /api/v1/profile HTTP/1.1
Host: portal.northwind-lab.local
Authorization: Bearer {access_token}
```

Portal validates:

- Token signature (JWKS from Entra)
- `aud` claim matches API application ID
- `scp` or `roles` claim includes required permission
- Token not expired

## Least Privilege

| Role | Scopes | API Access |
|------|--------|------------|
| Portal.User | `openid profile email api://northwind-portal/access` | Read own profile |
| Portal.Admin | Above + admin scope | Manage portal settings |

See [OIDC architecture](../oidc/architecture.md) and the [application onboarding runbook](../../application-onboarding/runbook.md).
