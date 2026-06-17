#Requires -Version 7.0
<#
.SYNOPSIS
    Verify Phase 3 RBAC and enterprise app assignments against the live tenant.
.EXAMPLE
    .\Verify-LabRbac.ps1
#>
[CmdletBinding()]
param()

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

$appsPath = Get-LabConfigPath 'apps.definition.json'
$usersPath = Get-LabConfigPath 'users.seed.json'
$appsConfig = Get-Content $appsPath -Raw | ConvertFrom-Json
$seed = Get-Content $usersPath -Raw | ConvertFrom-Json
$domain = (Get-LabEnv).DOMAIN
$groupMap = Get-LabGroupMap

$failures = 0
function Assert-Check {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if ($Condition) {
        Write-LabLog $Message 'SUCCESS'
    }
    else {
        Write-LabLog $Message 'ERROR'
        $script:failures++
    }
}

Write-LabLog 'Verifying RBAC and enterprise app assignments...' 'INFO'

$itAdmins = @($seed.users | Where-Object { $_.roleTier -eq 'IT-Administrator' -and -not $_.isBreakGlass })
foreach ($admin in $itAdmins) {
    $upn = Resolve-LabUserUpn -UserPrincipalName $admin.userPrincipalName
    $assignments = Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$((Get-LabUserByUpn -UserPrincipalName $upn).Id)'" -ErrorAction SilentlyContinue
    $gaAssignment = @($assignments | ForEach-Object {
        $def = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $_.RoleDefinitionId -ErrorAction SilentlyContinue
        $def
    } | Where-Object { $_.DisplayName -eq 'Global Administrator' })
    Assert-Check ($gaAssignment.Count -eq 0) "No standing Global Administrator on $upn"
}

$salesforceGroupId = $groupMap['SG-APP-Salesforce']
if ($salesforceGroupId) {
    $sfMembers = Get-MgGroupMember -GroupId $salesforceGroupId -All
    $sfMemberUsers = @($sfMembers | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
    $expectedSf = @($seed.users | Where-Object { $_.department -in @('Finance', 'Operations') -and $_.status -eq 'Active' }).Count
    Assert-Check ($sfMemberUsers.Count -eq $expectedSf) "SG-APP-Salesforce members: $($sfMemberUsers.Count) (expected Finance + Operations: $expectedSf)"
}

$m365GroupId = $groupMap['SG-APP-Microsoft365']
if ($m365GroupId) {
    $m365Members = Get-MgGroupMember -GroupId $m365GroupId -All
    $m365MemberUsers = @($m365Members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
    $expectedM365 = @($seed.users | Where-Object { $_.status -eq 'Active' }).Count
    Assert-Check ($m365MemberUsers.Count -eq $expectedM365) "SG-APP-Microsoft365 members: $($m365MemberUsers.Count) (expected all active employees: $expectedM365)"
}

foreach ($appDef in $appsConfig.enterpriseApplications) {
    $sp = Get-LabGraphObject (Get-MgServicePrincipal -Filter "displayName eq '$($appDef.displayName)'" -Property Id, DisplayName, AppRoles -ErrorAction SilentlyContinue)
    if (-not $sp) {
        $sp = Get-LabGraphObject (Get-MgServicePrincipal -Filter "displayName eq 'Microsoft 365'" -Property Id, DisplayName, AppRoles -ErrorAction SilentlyContinue)
    }
    if (-not $sp) {
        Assert-Check $false "Enterprise app '$($appDef.displayName)' is registered"
        continue
    }

    Assert-Check $true "Enterprise app '$($sp.DisplayName)' exists"

    foreach ($assignment in $appDef.assignedGroups) {
        if ($assignment.licenseAssignment) { continue }
        if (-not $groupMap.ContainsKey($assignment.group)) { continue }

        $groupId = $groupMap[$assignment.group]
        $roleValue = if ($assignment.appRole) { $assignment.appRole } else { 'Default Access' }
        $appRoleId = '00000000-0000-0000-0000-000000000000'
        if ($roleValue -ne 'Default Access') {
            $role = @($sp.AppRoles | Where-Object { $_.Value -eq $roleValue })
            if ($role.Count -gt 0) { $appRoleId = $role[0].Id.ToString() }
        }

        $assigned = @(Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All -ErrorAction SilentlyContinue `
            | Where-Object {
                $_.PrincipalId -eq $groupId -and
                $null -ne $_.AppRoleId -and
                $_.AppRoleId.ToString() -eq $appRoleId
            })
        Assert-Check ($assigned.Count -gt 0) "$($assignment.group) assigned to $($sp.DisplayName) ($roleValue)"
    }
}

foreach ($roleDef in $appsConfig.entraDirectoryRoles) {
    $roleTemplate = Get-LabGraphObject (Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$($roleDef.role)'" -ErrorAction SilentlyContinue)
    if (-not $roleTemplate) { continue }

    if ($roleDef.assignedGroup) {
        if (-not $groupMap.ContainsKey($roleDef.assignedGroup)) { continue }
        $groupId = $groupMap[$roleDef.assignedGroup]
        $group = Get-MgGroup -GroupId $groupId -Property IsAssignableToRole -ErrorAction SilentlyContinue
        if ($group.IsAssignableToRole) {
            $assignment = @(Get-MgRoleManagementDirectoryRoleAssignment -All -ErrorAction SilentlyContinue `
                | Where-Object { $_.RoleDefinitionId -eq $roleTemplate.Id -and $_.PrincipalId -eq $groupId })
            Assert-Check ($assignment.Count -gt 0) "$($roleDef.assignedGroup) has directory role '$($roleDef.role)'"
        }
        else {
            $members = @(Get-MgGroupMember -GroupId $groupId -All | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
            $expectedRoleTier = switch ($roleDef.role) {
                'User Administrator' { 'HR Administrator' }
                'Privileged Role Administrator' { 'IT Administrator' }
                default { $null }
            }
            $expectedMembers = @($members | Where-Object {
                $user = Get-MgUser -UserId $_.Id -Property UserPrincipalName -ErrorAction SilentlyContinue
                if (-not $user) { return $false }
                $seedUser = $seed.users | Where-Object {
                    (Resolve-LabUserUpn -UserPrincipalName $_.userPrincipalName) -eq $user.UserPrincipalName
                } | Select-Object -First 1
                if (-not $seedUser -or $seedUser.isBreakGlass) { return $false }
                if ($expectedRoleTier) { return $seedUser.roleTier -eq $expectedRoleTier }
                return $true
            })
            $assignedCount = 0
            foreach ($member in $expectedMembers) {
                $hasRole = @(Get-MgRoleManagementDirectoryRoleAssignment -All -ErrorAction SilentlyContinue `
                    | Where-Object { $_.RoleDefinitionId -eq $roleTemplate.Id -and $_.PrincipalId -eq $member.Id }).Count -gt 0
                if ($hasRole) { $assignedCount++ }
            }
            Assert-Check ($expectedMembers.Count -gt 0 -and $assignedCount -eq $expectedMembers.Count) "$($roleDef.assignedGroup) admin members have directory role '$($roleDef.role)' (Entra Free user assignment)"
        }
        continue
    }

    if ($roleDef.assignedTo) {
        $upn = Resolve-LabUserUpn -UserPrincipalName $roleDef.assignedTo[0]
        $user = Get-LabUserByUpn -UserPrincipalName $upn
        if (-not $user) { continue }
        $assignment = @(Get-MgRoleManagementDirectoryRoleAssignment -All -ErrorAction SilentlyContinue `
            | Where-Object { $_.RoleDefinitionId -eq $roleTemplate.Id -and $_.PrincipalId -eq $user.Id })
        Assert-Check ($assignment.Count -gt 0) "$upn has directory role '$($roleDef.role)'"
    }
}

if ($failures -eq 0) {
    Write-LabLog 'All RBAC checks passed.' 'SUCCESS'
    exit 0
}

Write-LabLog "$failures check(s) failed." 'ERROR'
exit 1
