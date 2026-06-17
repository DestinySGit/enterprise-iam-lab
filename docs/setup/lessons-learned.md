# Lessons Learned — Building on Entra ID Free

I built this lab on an Entra ID Free tenant. That constraint shaped the project more than any single technical decision.

## What Was Harder Than I Expected

**Licensing gaps show up everywhere.** Security defaults got me a real MFA baseline, but the moment I wanted custom Conditional Access, sign-in activity for inactive-user reporting, or Entra access review campaigns, I hit a wall. I ended up writing policy specs and runbooks that are production-ready on paper but not enforced in my tenant.

**Federation is two-sided.** Configuring SAML on the Entra gallery Salesforce app was straightforward. Proving end-to-end SSO without a Salesforce Developer org sitting next to it meant my portfolio evidence is split: live Entra captures plus documented flows. Same story for OIDC and SCIM on the Northwind Portal—I automated what Graph allows, but a hosted app at the redirect URI is still the missing piece for a full login loop.

**Graph permissions are easy to under-scope.** My automation app needed more than I initially granted (`User.ReadWrite.All`, group membership writes, app role assignment). `Fix-LabAppPermissions.ps1` exists because I made that mistake.

**Break-glass is simple until it isn't.** Standing Global Admin on `adm-breakglass` with a CA exclusion group is easy to document. What's harder is resisting the urge to give daily IT admins Active GA "just for convenience." I kept IT on Privileged Role Administrator and documented PIM patterns I haven't live-tested yet.

## What I'd Do With P1/P2 Licensing

If I had Entra ID P1 tomorrow, I'd do these in order:

1. **Disable Security defaults** and deploy the four CA policies in [ca-policies.spec.json](../../automation/config/ca-policies.spec.json) using the report-only → enforce sequence in [ca-rollout-runbook.md](./ca-rollout-runbook.md). I'd want real sign-in log evaluation before flipping enforcement.
2. **Re-run `Get-InactiveUsers.ps1`** and trust `SignInActivity` instead of the password-change proxy. Governance decisions on stale accounts need real last-sign-in data.
3. **Scope CA to federation apps**—Salesforce and Northwind Portal—as called out in the CA design docs, once baseline policies are stable.

With **P2** on top of that:

4. **Replace my hybrid quarterly procedure** with Entra access review campaigns for department groups and privileged roles, using [quarterly-review.md](../access-governance/quarterly-review.md) as the operator guide.
5. **Move IT admins to eligible Global Administrator via PIM** instead of standing directory roles. I'd keep `adm-breakglass` as the only Active GA, require MFA and justification on activation, and cap elevation at one hour. I haven't configured this in my tenant—it's the first thing I'd turn on with P2 because it directly addresses the standing-privilege problem I designed around.

## What I'd Do Differently If I Started Over

- **Get trial P1/P2 earlier** (Microsoft 365 Developer Program or a short SKU) so CA and governance aren't split between "live" and "documented."
- **Host a minimal Portal SPA sooner**—even a static site behind Entra OIDC—so token exchange and SCIM provisioning aren't only architecture diagrams.

The lab reads as "how I'd operate in production" even where the tenant can't run every blade. That's the bar I was aiming for.
