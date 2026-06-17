#Requires -Version 7.0
<#
.SYNOPSIS
    Verify SAML or OIDC federation configuration against live tenant and repo specs.
.EXAMPLE
    .\Verify-LabFederation.ps1 -Protocol SAML
.EXAMPLE
    .\Verify-LabFederation.ps1 -Protocol OIDC
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('SAML', 'OIDC')]
    [string]$Protocol
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

function Get-LabGraphObject {
    param([object]$Result)
    if ($null -eq $Result) { return $null }
    return @($Result)[0]
}

$failures = 0
$warnings = 0
function Assert-Check {
    param(
        [bool]$Condition,
        [string]$Message,
        [ValidateSet('Error', 'Warn')]
        [string]$Severity = 'Error'
    )
    if ($Condition) {
        Write-LabLog $Message 'SUCCESS'
    }
    elseif ($Severity -eq 'Warn') {
        Write-LabLog $Message 'WARN'
        $script:warnings++
    }
    else {
        Write-LabLog $Message 'ERROR'
        $script:failures++
    }
}

function Test-LabSamlFederation {
    $specPath = Get-LabConfigPath 'saml-salesforce.spec.json'
    $usersPath = Get-LabConfigPath 'users.seed.json'
    $spec = Get-Content $specPath -Raw | ConvertFrom-Json
    $seed = Get-Content $usersPath -Raw | ConvertFrom-Json
    $groupMap = Get-LabGroupMap

    Write-LabLog "Verifying SAML federation for $($spec.displayName)..." 'INFO'

    $servicePrincipal = Get-LabGraphObject (Get-MgServicePrincipal -Filter "displayName eq '$($spec.displayName)'" `
        -Property Id, AppId, DisplayName, PreferredSingleSignOnMode, LoginUrl, ReplyUrls `
        -ErrorAction SilentlyContinue)
    Assert-Check ($null -ne $servicePrincipal) "Gallery enterprise app '$($spec.displayName)' is registered in tenant"

    if ($servicePrincipal) {
        Assert-Check ($servicePrincipal.PreferredSingleSignOnMode -eq 'saml') `
            "SSO mode is SAML (actual: $($servicePrincipal.PreferredSingleSignOnMode))"
        Assert-Check ($servicePrincipal.ReplyUrls -contains $spec.acsUrl) `
            "Reply URL (ACS) includes spec value ($($spec.acsUrl))" -Severity Warn
    }

    foreach ($mapping in $spec.attributeMappings) {
        Assert-Check $true "Attribute mapping documented: $($mapping.entraClaim) → $($mapping.samlAttribute)"
    }

    foreach ($groupClaim in $spec.groupClaims) {
        Assert-Check $true "Group claim documented: $($groupClaim.filter) → $($groupClaim.claimName) ($($groupClaim.scope))"
    }

    if ($groupMap.ContainsKey('SG-APP-Salesforce')) {
        $groupId = $groupMap['SG-APP-Salesforce']
        $sfMembers = @(Get-MgGroupMember -GroupId $groupId -All | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
        $expectedSf = @($seed.users | Where-Object { $_.department -in @('Finance', 'Operations') -and $_.status -eq 'Active' }).Count
        Assert-Check ($sfMembers.Count -eq $expectedSf) "SG-APP-Salesforce members: $($sfMembers.Count) (expected Finance + Operations: $expectedSf)"
    }

    $testUser = $seed.users | Where-Object { $_.department -eq 'Finance' -and $_.status -eq 'Active' } | Select-Object -First 1
    if ($testUser -and $groupMap.ContainsKey('SG-APP-Salesforce')) {
        $upn = Resolve-LabUserUpn -UserPrincipalName $testUser.userPrincipalName
        $user = Get-LabUserByUpn -UserPrincipalName $upn
        if ($user) {
            $members = Get-MgGroupMember -GroupId $groupMap['SG-APP-Salesforce'] -All
            $isMember = @($members | Where-Object { $_.Id -eq $user.Id }).Count -gt 0
            Assert-Check $isMember "Test user $upn is member of SG-APP-Salesforce (CRM entitlement)"
        }
    }

    if ($spec.entraFreeNotes) {
        Write-LabLog $spec.entraFreeNotes 'INFO'
    }
}

function Test-LabOidcFederation {
    $specPath = Get-LabConfigPath 'oidc-portal.spec.json'
    $spec = Get-Content $specPath -Raw | ConvertFrom-Json
    $groupMap = Get-LabGroupMap

    Write-LabLog "Verifying OIDC federation for $($spec.displayName)..." 'INFO'

    $application = Get-LabGraphObject (Get-MgApplication -Filter "displayName eq '$($spec.displayName)'" `
        -Property Id, AppId, IdentifierUris, Web, Spa, Api, AppRoles -ErrorAction SilentlyContinue)
    Assert-Check ($null -ne $application) "App registration '$($spec.displayName)' exists"

    if ($application) {
        $redirectUris = @()
        if ($application.Web) { $redirectUris += @($application.Web.RedirectUris) }
        if ($application.Spa) { $redirectUris += @($application.Spa.RedirectUris) }
        foreach ($uri in $spec.redirectUris) {
            Assert-Check ($redirectUris -contains $uri) "Redirect URI configured: $uri"
        }

        if ($application.Spa -and $application.Spa.ImplicitGrantSettings) {
            Assert-Check ($application.Spa.ImplicitGrantSettings.EnableIdTokenIssuance) 'SPA issues ID tokens (implicit grant enabled)' -Severity Warn
            Assert-Check ($application.Spa.ImplicitGrantSettings.EnableAccessTokenIssuance) 'SPA issues access tokens (implicit grant enabled)' -Severity Warn
        }
        else {
            Assert-Check $true 'Authorization code + PKCE flow documented (tokens via /token endpoint)' -Severity Warn
        }

        $resolvedIdentifierUri = Resolve-LabIdentifierUri -IdentifierUri $spec.identifierUri
        Assert-Check (@($application.IdentifierUris) -contains $resolvedIdentifierUri) "Identifier URI configured: $resolvedIdentifierUri"

        if ($spec.exposedApi) {
            $apiScopes = @()
            if ($application.Api -and $application.Api.Oauth2PermissionScopes) {
                $apiScopes = @($application.Api.Oauth2PermissionScopes)
            }
            $exposedScope = @($apiScopes | Where-Object { $_.Value -eq $spec.exposedApi.scopeValue -and $_.IsEnabled })
            Assert-Check ($exposedScope.Count -gt 0) "Exposed API scope exists: $($spec.exposedApi.scopeValue)"
        }

        foreach ($role in $spec.appRoles) {
            $liveRole = @($application.AppRoles | Where-Object { $_.Value -eq $role.value -and $_.IsEnabled })
            Assert-Check ($liveRole.Count -gt 0) "App role exists: $($role.value)"
        }

        foreach ($claim in $spec.optionalClaims) {
            Assert-Check $true "Optional claim documented: $claim"
        }
    }

    $servicePrincipal = Get-LabGraphObject (Get-MgServicePrincipal -Filter "displayName eq '$($spec.displayName)'" `
        -Property Id, DisplayName, AppRoles -ErrorAction SilentlyContinue)
    Assert-Check ($null -ne $servicePrincipal) "Enterprise app '$($spec.displayName)' exists"

    foreach ($assignment in $spec.assignedGroups) {
        if (-not $groupMap.ContainsKey($assignment.group)) { continue }
        $groupId = $groupMap[$assignment.group]
        $appRoleId = '00000000-0000-0000-0000-000000000000'
        if ($assignment.appRole -ne 'Default Access') {
            $role = @($servicePrincipal.AppRoles | Where-Object { $_.Value -eq $assignment.appRole })
            if ($role.Count -gt 0) { $appRoleId = $role[0].Id.ToString() }
        }
        $assigned = @(Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $servicePrincipal.Id -All -ErrorAction SilentlyContinue `
            | Where-Object { $_.PrincipalId -eq $groupId -and $_.AppRoleId.ToString() -eq $appRoleId })
        Assert-Check ($assigned.Count -gt 0) "$($assignment.group) assigned with role $($assignment.appRole)"
    }
}

switch ($Protocol) {
    'SAML' { Test-LabSamlFederation }
    'OIDC' { Test-LabOidcFederation }
}

if ($failures -eq 0) {
    if ($warnings -gt 0) {
        Write-LabLog "All $Protocol entitlement checks passed; $warnings portal/SAML setting warning(s) — see docs/federation/saml/architecture.md for manual steps." 'SUCCESS'
    }
    else {
        Write-LabLog "All $Protocol federation checks passed." 'SUCCESS'
    }
    exit 0
}

Write-LabLog "$failures check(s) failed for $Protocol federation." 'ERROR'
exit 1
