# Quarterly Access Review Procedure

Access certification process for Northwind Collaborative — hybrid approach combining Entra ID portal campaigns with scripted reporting. Review scope includes federated applications (Salesforce, Northwind Employee Portal).

## Scope

| Review type | Frequency | Scope | Reviewer |
|-------------|-----------|-------|----------|
| Group membership | Quarterly | `SG-APP-*`, `SG-ROLE-*` | Group owners / managers |
| Federated app access | Quarterly | Salesforce, Northwind Portal | Group owners |
| Privileged roles | Quarterly | Entra directory role assignments | IT Security |
| Inactive accounts | Monthly (automated) | No sign-in ≥ 90 days | IAM team |

## Quarterly Campaign Setup (Portal)

1. **Entra ID > Identity Governance > Access reviews > New access review**
2. Configure:
   - **Review name:** `Q1-YYYY-App-Access-Review` (rotate quarter)
   - **Scope:** All users with access to selected groups
   - **Groups:** `SG-APP-Salesforce`, `SG-APP-NorthwindPortal`, `SG-ROLE-IT-Administrator`, `SG-ROLE-HR-Administrator`
   - **Reviewer:** Group owners (fallback: manager)
   - **Duration:** 14 days
   - **Auto-apply results:** Off for lab (manual remediation documented)
3. Launch campaign and notify reviewers (lab: self-review).
4. Export results: **Download CSV** after completion.

## Reviewer Instructions

1. Open the access review from **My Access** or email notification.
2. For each user, confirm access is still required.
3. Mark **Approve** if justified; **Deny** if access should be removed.
4. Add business justification for privileged role and federated app approvals.
5. Submit before deadline.

## Remediation SLA

| Finding | SLA | Action |
|---------|-----|--------|
| Denied app access | 48 hours | Remove from `SG-APP-*` group |
| Denied federated app access | 48 hours | Remove from group; verify SCIM deprovision |
| Denied privileged role | 24 hours | Remove directory role assignment |
| No reviewer response | End of campaign | Escalate to IAM lead |
| Inactive account | 7 days | Run `Get-InactiveUsers.ps1`; disable if confirmed |

## Automated Reports

### Inactive Users (90 days)

On **Entra ID P1/P2**, the script uses `SignInActivity` from Graph. On **Entra ID Free**, it automatically falls back to `lastPasswordChangeDateTime` (or account creation date) as an inactivity proxy — output includes a `DataSource` column.

```powershell
cd automation/scripts
.\Connect-LabTenant.ps1
.\Get-InactiveUsers.ps1 -InactiveDays 90
```

Output: `reports/inactive-users-<timestamp>.csv`

### RBAC Export (pre-review baseline)

```powershell
.\Export-RbacMatrix.ps1
```

Run before each quarterly campaign to establish baseline entitlements. Compare against [entitlement-matrix.md](./entitlement-matrix.md).

## Evidence Retention

Store in lab journal (local, not committed if containing tenant IDs):

- Campaign configuration screenshot (redacted)
- Completed review CSV export
- Remediation ticket log
- Inactive user report

Sample format: [reports/samples/access-certification-sample.csv](../../reports/samples/access-certification-sample.csv)

## Guest Access Policy (Documented)

Guests are out of scope for v1. Policy statement:

- B2B guests require sponsor approval from department manager.
- Guest accounts expire after 90 days unless renewed.
- Guests are in scope for quarterly access reviews when enabled.

## Campaign Checklist

- [ ] Entra ID P2 license active
- [ ] Group owners assigned in Entra ID
- [ ] Baseline RBAC export saved
- [ ] Entitlement matrix reviewed
- [ ] Campaign created and started
- [ ] Reviewers notified
- [ ] Results exported and remediated
- [ ] Redacted screenshot captured for GitHub

See [screenshot guide](../screenshots/README.md).

## Related Documents

- [Entitlement Matrix](./entitlement-matrix.md)
- [RBAC Matrix](../rbac/rbac-matrix.md)
- [Application Onboarding Runbook](../application-onboarding/runbook.md)
