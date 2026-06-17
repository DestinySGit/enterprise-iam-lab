# Conditional Access Rollout Runbook

Step-by-step operator guide for Conditional Access rollout. Policy definitions live in [ca-policies.spec.json](../../automation/config/ca-policies.spec.json).

## Choose Your Path

| Tenant tier | Live controls | Repo deliverables |
|-------------|---------------|-------------------|
| **Entra ID Free** (this lab default) | Security defaults + Authenticator | CA specs, checklist CSV, verification script |
| **Entra ID P1+** | Custom CA policies in portal | Full rollout below |

## Path A — Entra ID Free (Current Lab)

Security defaults provide baseline MFA for administrators without custom CA policies.

1. **Enable Security defaults** — Entra admin center → **Identity** → **Overview** → **Properties** → **Manage security defaults** → **Enabled**
2. **Enable Microsoft Authenticator** — **Protection** → **Authentication methods** → **Microsoft Authenticator** → Enable (push + number matching recommended)
3. **Register MFA** on operator admin and `adm-breakglass` at [mysignins.microsoft.com/security-info](https://mysignins.microsoft.com/security-info)
4. **Verify exclusions** — confirm `adm-breakglass` is in `SG-EXCLUDE-BreakGlass` (import scripts add this automatically)
5. **Run verification:**

```powershell
cd automation/scripts
.\Connect-LabTenant.ps1
.\Verify-LabAuthControls.ps1
.\Export-CaPolicyChecklist.ps1   # documents CA design for portfolio; no portal deploy on Free tier
```

6. **Capture screenshots** per [screenshot guide](../screenshots/README.md) — use Security defaults and Authentication methods blades if CA policies are unavailable

## Path B — Entra ID P1+ (Production-Style)

### Prerequisites

- [ ] MFA registered on operator admin and break-glass accounts
- [ ] `SG-EXCLUDE-BreakGlass` contains `adm-breakglass`
- [ ] Security defaults **disabled** before creating custom CA policies (they conflict)

### Step 1 — Export checklist

```powershell
cd automation/scripts
.\Export-CaPolicyChecklist.ps1
# Output: reports/ca-policy-checklist-<timestamp>.csv
```

### Step 2 — Create policies (report-only)

For each policy in the CSV, open **Entra admin center** → **Protection** → **Conditional Access** → **New policy**:

| Policy | Users | Exclude | Conditions | Grant | Session |
|--------|-------|---------|------------|-------|---------|
| CA-001-Block-Legacy-Auth | All users | `SG-EXCLUDE-BreakGlass` | Client apps: Exchange ActiveSync + Other | Block access | — |
| CA-002-Require-MFA-All-Users | All users | `SG-EXCLUDE-BreakGlass` | All cloud apps; modern clients | Require MFA | — |
| CA-003-Require-MFA-Admins | Directory roles: all admin roles | `SG-EXCLUDE-BreakGlass` | All cloud apps | Require MFA | Sign-in frequency: 4 hours |
| CA-004-Block-Unknown-Locations-Admins (optional) | Directory roles: all admin roles | `SG-EXCLUDE-BreakGlass` | Locations: All; exclude trusted | Block access | — |

Set **Enable policy** to **Report-only** for every policy initially.

### Step 3 — MFA registration pilot

Before enabling CA-002:

1. Add 1–2 test users to `SG-EXCLUDE-CA-ReportOnly` if needed during pilot
2. Have test users register Authenticator
3. Review **Monitoring** → **Sign-in logs** for successful MFA and CA evaluation
4. Remove pilot exclusions before enforcement

### Step 4 — Validate (48 hours)

Review sign-in logs for report-only hits. Confirm no unexpected blocks for modern auth clients.

```powershell
.\Verify-LabAuthControls.ps1
```

### Step 5 — Enable incrementally

1. Enable **CA-001** (legacy auth block)
2. Enable **CA-003** (admin MFA + 4h session)
3. Confirm all users MFA-registered
4. Enable **CA-002** (all users MFA)
5. Optional: configure trusted named locations → enable **CA-004**

### Step 6 — Screenshots

Capture and redact per [screenshot guide](../screenshots/README.md):

- `ca-policies-list.png`
- `ca-mfa-all-users.png`
- `mfa-registration-methods.png`

## Rollback

Set any policy to **Off** or **Report-only** in Entra admin center. Break-glass remains accessible via `SG-EXCLUDE-BreakGlass`.

## Related Docs

- [Conditional Access design](../architecture/conditional-access.md)
