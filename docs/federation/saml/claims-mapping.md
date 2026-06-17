# SAML Claims Mapping — Salesforce CRM

Attribute and group claim configuration for Entra ID → Salesforce SAML assertions (gallery enterprise application).

## User Attribute Claims

| Entra Source | SAML Attribute | Format | Purpose |
|--------------|----------------|--------|---------|
| `user.userprincipalname` | NameID | emailAddress | Unique user identifier |
| `user.mail` | emailaddress | — | Email address |
| `user.displayname` | displayName | — | Full name |
| `user.department` | department | — | Department for Salesforce profile |

Gallery Salesforce ships default claims for givenname, surname, emailaddress, and name. Add **department** manually if not present.

## Group Claims

| Scope | Filter | Claim Name | Purpose |
|-------|--------|------------|---------|
| Security groups | `displayName` = `SG-APP-Salesforce` | `groups` | CRM entitlement for Finance and Operations |

### Portal configuration

1. **Entra ID → Enterprise applications → Salesforce CRM → Single sign-on → Attributes & Claims**
2. **Edit group claim**
3. Select **Security groups**
4. Filter: `displayName` **Equals** `SG-APP-Salesforce`
5. Customize claim name: `groups`
6. Save

On Entra ID Free, this approach emits group membership in the assertion without assigning the security group to the enterprise application in **Users and groups**.

## Portal Configuration Steps

1. **Entra ID → Enterprise applications → Salesforce CRM → Single sign-on → Attributes & Claims**
2. Configure group claim per table above
3. Add `department` attribute claim if missing
4. Verify NameID format is `emailAddress` with UPN source

## Verification

- User in `SG-APP-Salesforce` — assertion includes `groups` claim
- User not in group — no CRM entitlement via group claim
- Inspect assertion via Entra sign-in logs or SAML tracer

Spec reference: [saml-salesforce.spec.json](../../../automation/config/saml-salesforce.spec.json)
