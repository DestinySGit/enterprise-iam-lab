#Requires -Version 7.0
<#
.SYNOPSIS
    Configure enterprise applications and Entra directory roles from apps.definition.json.
.DESCRIPTION
    Idempotent Phase 3 setup: app registrations, enterprise app group assignments,
    and least-privilege directory role assignments via security groups.
.EXAMPLE
    .\Configure-LabApps.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$requiredModules = @(
    'Microsoft.Graph.Applications'
    'Microsoft.Graph.Identity.Governance'
)

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

$DefaultAppRoleId = '00000000-0000-0000-0000-000000000000'
$appsPath = Get-LabConfigPath 'apps.definition.json'
$appsConfig = Get-Content $appsPath -Raw | ConvertFrom-Json
$groupMap = Get-LabGroupMap
$script:groupMap = $groupMap

function Get-LabGraphObject {
    param([object]$Result)
    if ($null -eq $Result) { return $null }
    return @($Result)[0]
}

function Get-LabServicePrincipalByDisplayName {
    param([string]$DisplayName)
    Get-LabGraphObject (Get-MgServicePrincipal -Filter "displayName eq '$DisplayName'" -Property Id, AppId, DisplayName, AppRoles -ErrorAction SilentlyContinue)
}

function Get-LabApplicationByDisplayName {
    param([string]$DisplayName)
    Get-LabGraphObject (Get-MgApplication -Filter "displayName eq '$DisplayName'" -Property Id, AppId, DisplayName, AppRoles, IdentifierUris -ErrorAction SilentlyContinue)
}

function Get-LabServicePrincipalByAppId {
    param([string]$AppId)
    Get-LabGraphObject (Get-MgServicePrincipal -Filter "appId eq '$AppId'" -Property Id, AppId, DisplayName, AppRoles -ErrorAction SilentlyContinue)
}

function Get-LabServicePrincipalForAssignment {
    param(
        [string]$AppId,
        [string]$DisplayName,
        [switch]$RequiresCustomRoles
    )

    for ($attempt = 1; $attempt -le 6; $attempt++) {
        $sp = Get-LabServicePrincipalByAppId -AppId $AppId
        if ($sp) {
            if (-not $RequiresCustomRoles -or @($sp.AppRoles).Count -gt 0) {
                return $sp
            }
        }
        Start-Sleep -Seconds 2
    }

    throw "Enterprise app '$DisplayName' is not ready for assignments — re-run Configure-LabApps.ps1"
}

function New-LabAppRoleDefinition {
    param(
        [pscustomobject]$RoleDef
    )
    @{
        AllowedMemberTypes = @($RoleDef.allowedMemberTypes)
        Description        = $RoleDef.displayName
        DisplayName        = $RoleDef.displayName
        Id                 = [guid]::NewGuid().ToString()
        IsEnabled          = $true
        Value              = $RoleDef.value
    }
}

function Ensure-LabAppRegistration {
    param(
        [pscustomobject]$AppDef
    )

    $app = Get-LabApplicationByDisplayName -DisplayName $AppDef.displayName
    if ($app) {
        Write-LabLog "App registration '$($AppDef.displayName)' already exists — skipping create" 'WARN'
        return $app
    }

    $params = @{
        DisplayName     = $AppDef.displayName
        SignInAudience  = 'AzureADMyOrg'
    }
    if ($AppDef.identifierUri) {
        $params.IdentifierUris = @(Resolve-LabIdentifierUri -IdentifierUri $AppDef.identifierUri)
    }
    if ($AppDef.appRoles) {
        $params.AppRoles = @($AppDef.appRoles | ForEach-Object { New-LabAppRoleDefinition -RoleDef $_ })
    }

    $app = Invoke-GraphWithRetry {
        New-MgApplication @params -ErrorAction Stop
    }
    if (-not $app -or [string]::IsNullOrWhiteSpace($app.AppId)) {
        throw "Failed to create app registration '$($AppDef.displayName)'"
    }

    Write-LabLog "Created app registration '$($AppDef.displayName)' ($($app.AppId))" 'SUCCESS'
    return $app
}

function Ensure-LabServicePrincipal {
    param(
        [string]$AppId,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($AppId)) {
        throw "Cannot create enterprise app '$DisplayName' without a valid AppId"
    }

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $sp = Get-LabServicePrincipalByAppId -AppId $AppId
        if ($sp) {
            if ($attempt -gt 1) {
                Write-LabLog "Enterprise app '$DisplayName' available after propagation" 'INFO'
            }
            else {
                Write-LabLog "Enterprise app '$DisplayName' already exists — skipping create" 'WARN'
            }
            return $sp
        }
        Start-Sleep -Seconds 3
    }

    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $sp = Invoke-GraphWithRetry {
                New-MgServicePrincipal -BodyParameter @{ AppId = $AppId } -ErrorAction Stop
            }
            break
        }
        catch {
            if ($attempt -lt 5 -and $_.Exception.Message -match 'does not reference a valid application|NotFound') {
                Write-LabLog "Waiting for app registration propagation ($attempt/5)..." 'WARN'
                Start-Sleep -Seconds 3
                continue
            }
            throw
        }
    }
    if (-not $sp -or [string]::IsNullOrWhiteSpace($sp.Id)) {
        throw "Failed to create enterprise app '$DisplayName'"
    }

    Write-LabLog "Created enterprise app '$DisplayName'" 'SUCCESS'
    Start-Sleep -Seconds 3
    return (Get-LabServicePrincipalByAppId -AppId $AppId)
}

function Resolve-LabFirstPartyServicePrincipal {
    param([string]$DisplayName)

    $candidates = @(
        $DisplayName
        'Microsoft 365'
        'Office 365'
        'Office365'
    ) | Select-Object -Unique

    foreach ($name in $candidates) {
        $sp = Get-LabServicePrincipalByDisplayName -DisplayName $name
        if ($sp) {
            Write-LabLog "Using first-party enterprise app '$($sp.DisplayName)' for $DisplayName assignments" 'INFO'
            return $sp
        }
    }

    return $null
}

function Get-LabAppRoleId {
    param(
        [object]$ServicePrincipal,
        [string]$RoleValue
    )

    if (-not $ServicePrincipal -or [string]::IsNullOrWhiteSpace($ServicePrincipal.Id)) {
        throw "Enterprise app is missing — cannot resolve app role '$RoleValue'"
    }

    if ([string]::IsNullOrWhiteSpace($RoleValue) -or $RoleValue -eq 'Default Access') {
        return $DefaultAppRoleId
    }

    $role = @($ServicePrincipal.AppRoles | Where-Object { $_.Value -eq $RoleValue -and $_.IsEnabled })
    if ($role.Count -eq 0) {
        throw "App role '$RoleValue' not found on enterprise app '$($ServicePrincipal.DisplayName)'"
    }
    return $role[0].Id.ToString()
}

function Get-LabServicePrincipalAppRoleAssignments {
    param(
        [string]$ServicePrincipalId,
        [int]$MaxAttempts = 6
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return @(Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ServicePrincipalId -All -ErrorAction Stop)
        }
        catch {
            if ($attempt -ge $MaxAttempts -or $_.Exception.Message -notmatch 'NotFound|does not exist') {
                throw
            }
            Start-Sleep -Seconds 2
        }
    }
}

function Add-LabEnterpriseAppAssignment {
    param(
        [string]$AppId,
        [string]$DisplayName,
        [string]$GroupName,
        [string]$AppRoleValue
    )

    if (-not $groupMap.ContainsKey($GroupName)) {
        throw "Group '$GroupName' not found — run Import-LabGroups.ps1 first"
    }

    $requiresCustomRoles = -not [string]::IsNullOrWhiteSpace($AppRoleValue) -and $AppRoleValue -ne 'Default Access'
    $ServicePrincipal = Get-LabServicePrincipalForAssignment -AppId $AppId -DisplayName $DisplayName -RequiresCustomRoles:$requiresCustomRoles

    $groupId = $groupMap[$GroupName]
    $appRoleId = Get-LabAppRoleId -ServicePrincipal $ServicePrincipal -RoleValue $AppRoleValue

    $existing = @(Get-LabServicePrincipalAppRoleAssignments -ServicePrincipalId $ServicePrincipal.Id `
        | Where-Object {
            $_.PrincipalId -eq $groupId -and
            $null -ne $_.AppRoleId -and
            $_.AppRoleId.ToString() -eq $appRoleId
        })

    if ($existing) {
        Write-LabLog "$GroupName already assigned to $DisplayName ($AppRoleValue) — skipping" 'WARN'
        return
    }

    Invoke-GraphWithRetry {
        New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $ServicePrincipal.Id -BodyParameter @{
            PrincipalId = [string]$groupId
            ResourceId  = [string]$ServicePrincipal.Id
            AppRoleId   = [string]$appRoleId
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Assigned $GroupName → $DisplayName ($AppRoleValue)" 'SUCCESS'
}

function Add-LabDirectoryRoleAssignment {
    param(
        [string]$RoleName,
        [string]$PrincipalId,
        [string]$PrincipalLabel
    )

    $roleDef = Get-LabGraphObject (Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$RoleName'" -ErrorAction SilentlyContinue)
    if (-not $roleDef) {
        throw "Directory role '$RoleName' not found"
    }

    $existing = @(Get-MgRoleManagementDirectoryRoleAssignment -All -ErrorAction SilentlyContinue `
        | Where-Object { $_.RoleDefinitionId -eq $roleDef.Id -and $_.PrincipalId -eq $PrincipalId })
    if ($existing.Count -gt 0) {
        Write-LabLog "$PrincipalLabel already has '$RoleName' — skipping" 'WARN'
        return
    }

    Invoke-GraphWithRetry {
        New-MgRoleManagementDirectoryRoleAssignment -BodyParameter @{
            RoleDefinitionId = $roleDef.Id
            PrincipalId      = $PrincipalId
            DirectoryScopeId = '/'
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Assigned '$RoleName' → $PrincipalLabel" 'SUCCESS'
}

function Add-LabDirectoryRoleForGroup {
    param(
        [string]$RoleName,
        [string]$GroupName
    )

    if (-not $script:groupMap.ContainsKey($GroupName)) {
        throw "Group '$GroupName' not found — run Import-LabGroups.ps1 first"
    }

    $groupId = $script:groupMap[$GroupName]
    $group = Get-MgGroup -GroupId $groupId -Property Id, DisplayName, IsAssignableToRole -ErrorAction Stop

    if ($group.IsAssignableToRole) {
        Add-LabDirectoryRoleAssignment -RoleName $RoleName -PrincipalId $groupId -PrincipalLabel $GroupName
        return
    }

    Write-LabLog "Entra Free: assigning '$RoleName' to admin members of $GroupName (group-based roles require P1/P2)" 'WARN'
    $members = @(Get-MgGroupMember -GroupId $groupId -All | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
    if ($members.Count -eq 0) {
        throw "Group '$GroupName' has no members — run Import-LabUsers.ps1 first"
    }

    $seedPath = Get-LabConfigPath 'users.seed.json'
    $seed = Get-Content $seedPath -Raw | ConvertFrom-Json
    $expectedRoleTier = switch ($RoleName) {
        'User Administrator' { 'HR Administrator' }
        'Privileged Role Administrator' { 'IT Administrator' }
        default { $null }
    }

    foreach ($member in $members) {
        $user = Get-MgUser -UserId $member.Id -Property UserPrincipalName -ErrorAction Stop
        $seedUser = $seed.users | Where-Object {
            (Resolve-LabUserUpn -UserPrincipalName $_.userPrincipalName) -eq $user.UserPrincipalName
        } | Select-Object -First 1

        if ($expectedRoleTier -and $seedUser.roleTier -ne $expectedRoleTier) {
            continue
        }
        if ($seedUser.isBreakGlass) {
            continue
        }

        Add-LabDirectoryRoleAssignment -RoleName $RoleName -PrincipalId $member.Id -PrincipalLabel $user.UserPrincipalName
    }
}

Write-LabLog 'Configuring enterprise applications and directory roles...' 'INFO'

foreach ($appDef in $appsConfig.enterpriseApplications) {
    Write-LabLog "Processing $($appDef.displayName)..." 'INFO'

    $servicePrincipal = $null
    $isFirstParty = $appDef.displayName -eq 'Microsoft 365'

    if ($isFirstParty) {
        $servicePrincipal = Resolve-LabFirstPartyServicePrincipal -DisplayName $appDef.displayName
        if (-not $servicePrincipal) {
            Write-LabLog "First-party '$($appDef.displayName)' not found — creating lab stub registration" 'WARN'
            $application = Ensure-LabAppRegistration -AppDef $appDef
            $servicePrincipal = Ensure-LabServicePrincipal -AppId $application.AppId -DisplayName $appDef.displayName
        }
    }
    else {
        $application = Ensure-LabAppRegistration -AppDef $appDef
        $servicePrincipal = Ensure-LabServicePrincipal -AppId $application.AppId -DisplayName $appDef.displayName
    }

    foreach ($assignment in $appDef.assignedGroups) {
        if ($assignment.licenseAssignment) {
            Write-LabLog "License assignment for $($assignment.group) skipped (Entra Free — no M365 SKU)" 'WARN'
            continue
        }

        $appId = if ($application) { $application.AppId } else { $servicePrincipal.AppId }
        $roleValue = if ($assignment.appRole) { $assignment.appRole } else { 'Default Access' }
        Add-LabEnterpriseAppAssignment -AppId $appId -DisplayName $appDef.displayName -GroupName $assignment.group -AppRoleValue $roleValue
    }
}

Write-LabLog 'Configuring Entra directory roles...' 'INFO'

foreach ($roleDef in $appsConfig.entraDirectoryRoles) {
    if ($roleDef.assignedGroup) {
        Add-LabDirectoryRoleForGroup -RoleName $roleDef.role -GroupName $roleDef.assignedGroup
    }
    elseif ($roleDef.assignedTo) {
        foreach ($upn in @($roleDef.assignedTo)) {
            $resolvedUpn = Resolve-LabUserUpn -UserPrincipalName $upn
            $user = Get-LabUserByUpn -UserPrincipalName $resolvedUpn
            if (-not $user) {
                throw "User '$resolvedUpn' not found — run Import-LabUsers.ps1 first"
            }
            Add-LabDirectoryRoleAssignment -RoleName $roleDef.role -PrincipalId $user.Id -PrincipalLabel $resolvedUpn
        }
    }
}

Write-LabLog 'Enterprise app and directory role configuration complete.' 'SUCCESS'
