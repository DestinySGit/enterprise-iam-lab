# Security Policy

This repository documents an **Enterprise IAM Lab** using synthetic users and fictional organization data (Northwind Collaborative). It must never contain live tenant secrets.

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest `main` | Yes |

## Reporting a Vulnerability

If you discover a security issue in this repository (for example, committed credentials or personal data):

1. **Do not** open a public GitHub issue with sensitive details.
2. Contact the repository owner via GitHub private security advisory or direct message.
3. Include the file path, commit hash (if applicable), and a brief description.

## What Must Never Be Committed

| Artifact | Location | Risk |
|----------|----------|------|
| Tenant `.env` | `automation/.env` | Client ID, tenant ID, certificate thumbprint |
| Certificates / keys | `*.pfx`, `*.pem`, `secrets/` | Authentication material |
| Live report exports | `reports/*.csv` (except `reports/samples/`) | Real UPNs, sign-in data |
| SCIM / OAuth secrets | Any path | Bearer tokens, client secrets |
| Screenshot GUIDs | `docs/screenshots/` | Tenant and object identifiers |

`.gitignore` blocks the common cases. Always review `git status` and `git diff` before committing.

## Pre-Commit Checklist

```powershell
git status
git diff --staged
```

Confirm **none** of the following appear:

- [ ] `.env` or `automation.env`
- [ ] `*.pfx` / `*.pem`
- [ ] `reports/` CSV files outside `reports/samples/`
- [ ] Unredacted tenant GUIDs, client IDs, or object IDs in docs or screenshots
- [ ] Personal admin UPNs you prefer to keep private

## Operator Hygiene

- Store the app registration certificate in the **local machine** certificate store only.
- Copy `automation/.env.example` to `automation/.env` locally; never commit `.env`.
- Redact identifiers in portfolio screenshots per [docs/screenshots/README.md](docs/screenshots/README.md).
- Use fictional `@northwindcollab.onmicrosoft.com` UPNs in committed samples.

## Synthetic Data

All users, groups, and org structure in `automation/config/` are fictional. Replace `DOMAIN` in your local `.env` with your lab tenant domain for operator scripts only.

## License Scope

MIT applies to documentation and automation in this repo. Microsoft Entra ID and Microsoft Graph are Microsoft products; this project is independent and not affiliated with Microsoft.
