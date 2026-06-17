# Enterprise Application Onboarding Runbook

Standard procedure for onboarding applications to Northwind Collaborative via Microsoft Entra ID. Used for **Salesforce CRM** (SAML, gallery app) and **Northwind Employee Portal** (OIDC/SCIM).

## Onboarding Steps

```text
1. Discovery and entitlement design
2. Group-based access assignment
3. Protocol configuration — SAML or OIDC
4. SCIM provisioning (if applicable)
5. CA/MFA scoping
6. Access review inclusion
```

## Discovery

| Item | Document |
|------|----------|
| Application name and owner | Ticket / lab journal |
| Protocol (SAML, OIDC, both) | Architecture review |
| Data classification | Security review |
| Required user attributes | Claims mapping spec |
| Group-based entitlement model | RBAC matrix |

## Group and RBAC Setup

1. Create `SG-APP-{AppName}` security group
2. Add group to [groups.definition.json](../../automation/config/groups.definition.json)
3. Run `Import-LabGroups.ps1` (new groups) or assign manually
4. Add application to [apps.definition.json](../../automation/config/apps.definition.json)
5. Run `Configure-LabApps.ps1`
6. Verify with `Verify-LabRbac.ps1`
7. Export baseline: `Export-RbacMatrix.ps1`

## Protocol Configuration

### SAML Applications (e.g., Salesforce)

1. **Entra ID → Enterprise applications → New application → Browse gallery → Salesforce**
2. Open **Salesforce CRM → Single sign-on** (SAML is the default for the gallery app)
3. Set Identifier (Entity ID) and Reply URL (ACS) per [saml-salesforce.spec.json](../../automation/config/saml-salesforce.spec.json)
4. Configure attributes and group claims per [claims-mapping.md](../federation/saml/claims-mapping.md)
5. On Entra Free: use Security groups claim + assign pilot users individually
6. Test SSO with pilot user (or document Entra-side simulation)
7. Document in [docs/federation/saml/](../federation/saml/)

### OIDC Applications (e.g., Northwind Portal)

1. Create or extend app registration
2. Configure redirect URIs and token settings
3. Define app roles (`Portal.User`, `Portal.Admin`)
4. Enable group and optional claims
5. Assign groups to app roles via enterprise application
6. Test authorization code flow
7. Document in [docs/federation/oidc/](../federation/oidc/)

## SCIM Provisioning (Optional)

1. Enable provisioning on enterprise application
2. Configure SCIM endpoint and secret
3. Map attributes per [attribute-mapping.md](../federation/scim/attribute-mapping.md)
4. Test with Joiner/Leaver scripts
5. Monitor provisioning logs

## Security Controls

1. Confirm application appears in CA policy cloud app scope
2. Verify MFA enforced on application sign-in
3. Exclude break-glass account via `SG-EXCLUDE-BreakGlass`
4. Capture redacted screenshots

## Governance

1. Add application to entitlement matrix: [entitlement-matrix.md](../access-governance/entitlement-matrix.md)
2. Assign group owner for access review
3. Include in quarterly review scope: [quarterly-review.md](../access-governance/quarterly-review.md)

## Onboarding Checklist

- [ ] Application owner identified
- [ ] `SG-APP-*` group created and populated
- [ ] Enterprise app / app registration configured
- [ ] SSO protocol configured (SAML or OIDC)
- [ ] Claims mapping documented
- [ ] SCIM provisioning configured (if applicable)
- [ ] CA policies scope the application
- [ ] Entitlement matrix updated
- [ ] Access review scope updated
- [ ] Redacted screenshots captured

## Lab Applications

| Application | Protocol | Spec File |
|-------------|----------|-----------|
| Salesforce CRM | SAML (gallery) | [saml-salesforce.spec.json](../../automation/config/saml-salesforce.spec.json) |
| Northwind Employee Portal | OIDC + SCIM | [oidc-portal.spec.json](../../automation/config/oidc-portal.spec.json) |
| Microsoft 365 | First-party | [apps.definition.json](../../automation/config/apps.definition.json) |
