#Requires -Version 7.0
<#
.SYNOPSIS
    Export RBAC matrix mapping role tiers and groups to applications.
.PARAMETER OutputPath
.EXAMPLE
    .\Export-RbacMatrix.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

$appsPath = Get-LabConfigPath 'apps.definition.json'
$groupsPath = Get-LabConfigPath 'groups.definition.json'
$appsConfig = Get-Content $appsPath -Raw | ConvertFrom-Json
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Get-LabReportsPath "rbac-matrix-$stamp.csv"
}

$rows = @()

foreach ($app in $appsConfig.enterpriseApplications) {
    foreach ($assignment in $app.assignedGroups) {
        $rows += [pscustomobject]@{
            Application   = $app.displayName
            Group         = $assignment.group
            AccessLevel   = if ($assignment.appRole) { $assignment.appRole } else { 'Default Access' }
            AssignmentType = if ($assignment.licenseAssignment) { 'License' } else { 'App Role' }
        }
    }
}

foreach ($role in $appsConfig.entraDirectoryRoles) {
    $assignedTo = if ($role.assignedGroup) { $role.assignedGroup } else { ($role.assignedTo -join '; ') }
    $rows += [pscustomobject]@{
        Application    = 'Microsoft Entra ID'
        Group          = $assignedTo
        AccessLevel    = $role.role
        AssignmentType = 'Directory Role'
    }
}

foreach ($group in ($groupConfig.groups | Where-Object { $_.groupType -eq 'Role' })) {
    $memberCount = 0
    $g = Get-MgGroup -Filter "displayName eq '$($group.displayName)'" -ErrorAction SilentlyContinue
    if ($g) {
        $groupId = @($g)[0].Id
        $members = Get-MgGroupMember -GroupId $groupId -All -ErrorAction SilentlyContinue
        $memberCount = @($members).Count
    }
    $rows += [pscustomobject]@{
        Application    = 'Internal RBAC'
        Group          = $group.displayName
        AccessLevel    = $group.description
        AssignmentType = "Role Group ($memberCount members)"
    }
}

$rows | Sort-Object Application, Group | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-LabLog "Exported RBAC matrix ($($rows.Count) rows) to $OutputPath" 'SUCCESS'
$rows | Format-Table -AutoSize
