#Requires -Version 7.0
<#
.SYNOPSIS
    Configure OIDC/OAuth settings on Northwind Employee Portal from oidc-portal.spec.json.
.DESCRIPTION
    Idempotent Phase 5 setup: SPA redirect URIs, implicit grant tokens, optional claims,
    exposed API scope, and delegated API permission for the Portal client.
.EXAMPLE
    .\Configure-LabOidcApps.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$requiredModules = @('Microsoft.Graph.Applications')
foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-LabLog "Installing $mod..." 'INFO'
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $mod -ErrorAction Stop
}

& (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null

if (-not (Test-LabGraphScopes -RequiredScopes (Get-LabRbacAppScopes) -FailOnMissing)) {
    throw 'Missing RBAC scopes. Run Fix-LabAppPermissions.ps1 as Global Administrator, then Connect-LabTenant.ps1.'
}

$specPath = Get-LabConfigPath 'oidc-portal.spec.json'
$spec = Get-Content $specPath -Raw | ConvertFrom-Json

function Get-LabGraphObject {
    param([object]$Result)
    if ($null -eq $Result) { return $null }
    return @($Result)[0]
}

function Get-LabApplicationByDisplayName {
    param([string]$DisplayName)
    Get-LabGraphObject (Get-MgApplication -Filter "displayName eq '$DisplayName'" `
        -Property Id, AppId, DisplayName, IdentifierUris, Spa, Web, Api, OptionalClaims, RequiredResourceAccess `
        -ErrorAction SilentlyContinue)
}

function Get-LabOptionalClaimBody {
    param([string]$ClaimName)

    switch ($ClaimName) {
        'groups' {
            return @{
                Name                 = 'groups'
                Essential            = $false
                AdditionalProperties = @{ include = $spec.groupClaims.include }
            }
        }
        default {
            return @{
                Name      = $ClaimName
                Essential = $false
            }
        }
    }
}

function Ensure-LabOidcApplication {
    $application = Get-LabApplicationByDisplayName -DisplayName $spec.displayName
    if (-not $application) {
        throw "App registration '$($spec.displayName)' not found — run Configure-LabApps.ps1 first"
    }
    return $application
}

function Ensure-LabOidcSpaConfiguration {
    param(
        [object]$Application
    )

    $existingUris = @()
    if ($Application.Spa -and $Application.Spa.RedirectUris) {
        $existingUris = @($Application.Spa.RedirectUris)
    }
    $redirectUris = @($existingUris + @($spec.redirectUris) | Where-Object { $_ } | Select-Object -Unique)

    $enableIdToken = if ($null -ne $spec.implicitGrant.enableIdTokenIssuance) {
        [bool]$spec.implicitGrant.enableIdTokenIssuance
    } else { $true }
    $enableAccessToken = if ($null -ne $spec.implicitGrant.enableAccessTokenIssuance) {
        [bool]$spec.implicitGrant.enableAccessTokenIssuance
    } else { $true }

    $spaBody = @{
        RedirectUris = $redirectUris
    }

    Invoke-GraphWithRetry {
        Update-MgApplication -ApplicationId $Application.Id -BodyParameter @{
            Spa = $spaBody
        } -ErrorAction Stop | Out-Null
    }

    Write-LabLog "Configured SPA redirect URIs ($($redirectUris.Count))" 'SUCCESS'
    if ($enableIdToken -or $enableAccessToken) {
        Write-LabLog 'Enable ID/access token implicit grant in portal if using hybrid flow; authorization code + PKCE obtains tokens via /token endpoint' 'INFO'
    }
}

function Ensure-LabOidcIdentifierUri {
    param(
        [object]$Application
    )

    $identifierUri = Resolve-LabIdentifierUri -IdentifierUri $spec.identifierUri
    $existingUris = @($Application.IdentifierUris)
    if ($existingUris -contains $identifierUri) {
        Write-LabLog "Identifier URI already set: $identifierUri" 'WARN'
        return $identifierUri
    }

    $mergedUris = @($existingUris + $identifierUri | Select-Object -Unique)
    Invoke-GraphWithRetry {
        Update-MgApplication -ApplicationId $Application.Id -BodyParameter @{
            IdentifierUris = $mergedUris
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Set identifier URI: $identifierUri" 'SUCCESS'
    return $identifierUri
}

function Ensure-LabOidcOptionalClaims {
    param(
        [object]$Application
    )

    $idTokenClaims = @($spec.optionalClaims | ForEach-Object { Get-LabOptionalClaimBody -ClaimName $_ })
    $accessTokenClaims = @(
        Get-LabOptionalClaimBody -ClaimName 'groups'
    )

    Invoke-GraphWithRetry {
        Update-MgApplication -ApplicationId $Application.Id -BodyParameter @{
            OptionalClaims = @{
                IdToken     = $idTokenClaims
                AccessToken = $accessTokenClaims
            }
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Configured optional claims: $($spec.optionalClaims -join ', ')" 'SUCCESS'
}

function Ensure-LabOidcExposedApi {
    param(
        [object]$Application,
        [string]$IdentifierUri
    )

    $scopeValue = $spec.exposedApi.scopeValue
    $existingScopes = @()
    if ($Application.Api -and $Application.Api.Oauth2PermissionScopes) {
        $existingScopes = @($Application.Api.Oauth2PermissionScopes)
    }

    $scopeId = [guid]::NewGuid().ToString()
    $existingScope = @($existingScopes | Where-Object { $_.Value -eq $scopeValue })
    if ($existingScope.Count -gt 0) {
        $scopeId = $existingScope[0].Id.ToString()
        Write-LabLog "Exposed API scope '$scopeValue' already exists — preserving scope ID" 'WARN'
    }

    $scopeDef = @{
        AdminConsentDescription = $spec.exposedApi.adminConsentDescription
        AdminConsentDisplayName = $spec.exposedApi.adminConsentDisplayName
        Id                      = $scopeId
        IsEnabled               = $true
        Type                    = 'User'
        UserConsentDescription  = $spec.exposedApi.userConsentDescription
        UserConsentDisplayName  = $spec.exposedApi.userConsentDisplayName
        Value                   = $scopeValue
    }

    $otherScopes = @($existingScopes | Where-Object { $_.Value -ne $scopeValue })
    $apiBody = @{
        RequestedAccessTokenVersion = 2
        Oauth2PermissionScopes        = @($otherScopes + $scopeDef)
    }

    Invoke-GraphWithRetry {
        Update-MgApplication -ApplicationId $Application.Id -BodyParameter @{
            Api = $apiBody
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Exposed API scope: $IdentifierUri/$scopeValue" 'SUCCESS'
    return $scopeId
}

function Ensure-LabOidcDelegatedPermission {
    param(
        [object]$Application,
        [string]$ScopeId
    )

    $requiredAccess = @($Application.RequiredResourceAccess)
    $selfResource = @($requiredAccess | Where-Object { $_.ResourceAppId -eq $Application.AppId })
    $otherResources = @($requiredAccess | Where-Object { $_.ResourceAppId -ne $Application.AppId })

    $scopeEntry = @{
        Id   = $ScopeId
        Type = 'Scope'
    }

    if ($selfResource.Count -gt 0) {
        $existingScopes = @($selfResource[0].ResourceAccess | ForEach-Object { $_.Id.ToString() })
        if ($existingScopes -contains $ScopeId) {
            Write-LabLog 'Delegated API permission for exposed scope already configured' 'WARN'
            return
        }
        $mergedScopes = @($selfResource[0].ResourceAccess) + @($scopeEntry)
        $selfResource[0].ResourceAccess = $mergedScopes
    }
    else {
        $selfResource = @([pscustomobject]@{
            ResourceAppId  = $Application.AppId
            ResourceAccess = @($scopeEntry)
        })
    }

    $updatedAccess = @($otherResources + $selfResource)
    Invoke-GraphWithRetry {
        Update-MgApplication -ApplicationId $Application.Id -BodyParameter @{
            RequiredResourceAccess = $updatedAccess
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog 'Added delegated permission for exposed API scope' 'SUCCESS'
}

Write-LabLog "Configuring OIDC/OAuth for $($spec.displayName)..." 'INFO'

$application = Ensure-LabOidcApplication
$identifierUri = Ensure-LabOidcIdentifierUri -Application $application
Ensure-LabOidcSpaConfiguration -Application $application
Ensure-LabOidcOptionalClaims -Application $application
$scopeId = Ensure-LabOidcExposedApi -Application $application -IdentifierUri $identifierUri
Ensure-LabOidcDelegatedPermission -Application $application -ScopeId $scopeId

if ($spec.notes) {
    Write-LabLog $spec.notes 'INFO'
}
if ($spec.entraFreeNotes) {
    Write-LabLog $spec.entraFreeNotes 'INFO'
}

Write-LabLog 'OIDC/OAuth configuration complete. Run Verify-LabFederation.ps1 -Protocol OIDC to validate.' 'SUCCESS'
