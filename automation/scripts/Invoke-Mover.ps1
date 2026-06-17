#Requires -Version 7.0
<#
.SYNOPSIS
    Mover workflow — update department/role and swap group memberships.
.PARAMETER UserPrincipalName
.PARAMETER NewDepartment
.PARAMETER NewJobTitle
.PARAMETER NewRoleTier
.PARAMETER NewManagerUpn
.EXAMPLE
    .\Invoke-Mover.ps1 -UserPrincipalName 'james.anderson@northwindcollab.onmicrosoft.com' -NewDepartment 'IT' -NewJobTitle 'IT Project Coordinator' -NewRoleTier 'Employee' -NewManagerUpn 'robert.campbell@northwindcollab.onmicrosoft.com'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UserPrincipalName,
    [Parameter(Mandatory = $true)][ValidateSet('HR', 'Finance', 'IT', 'Engineering', 'Operations')][string]$NewDepartment,
    [Parameter(Mandatory = $true)][string]$NewJobTitle,
    [Parameter(Mandatory = $true)][ValidateSet('Employee', 'Manager', 'IT Administrator', 'HR Administrator')][string]$NewRoleTier,
    [string]$NewManagerUpn
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$groupsPath = Get-LabConfigPath 'groups.definition.json'
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json
$rules = $groupConfig.membershipRules
$groupMap = Get-LabGroupMap

$user = Get-LabUserByUpn -UserPrincipalName $UserPrincipalName
if (-not $user) { throw "User $UserPrincipalName not found." }

$oldDept = $user.Department
$oldUserObject = [pscustomobject]@{
    userPrincipalName = $UserPrincipalName
    department        = $oldDept
    roleTier          = 'Employee'
    status            = 'Active'
}

$newUserObject = [pscustomobject]@{
    userPrincipalName = $UserPrincipalName
    department        = $NewDepartment
    roleTier          = $NewRoleTier
    status            = 'Active'
}

$updateParams = @{
    Department = $NewDepartment
    JobTitle   = $NewJobTitle
}
Invoke-GraphWithRetry { Update-MgUser -UserId $user.Id -BodyParameter $updateParams }
Write-LabLog "Updated profile for $UserPrincipalName" 'INFO'

if ($NewManagerUpn) {
    $manager = Get-LabUserByUpn -UserPrincipalName $NewManagerUpn
    if (-not $manager) { throw "Manager $NewManagerUpn not found." }
    Invoke-GraphWithRetry {
        Set-MgUserManagerByRef -UserId $user.Id -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)" }
    }
}

$oldGroups = Resolve-LabGroupNamesForUser -User $oldUserObject -Rules $rules
$newGroups = Resolve-LabGroupNamesForUser -User $newUserObject -Rules $rules

$deptPrefix = 'SG-DEPT-'
$rolePrefix = 'SG-ROLE-'
$appPrefix = 'SG-APP-'

foreach ($groupName in $oldGroups) {
    if ($groupName -like "$deptPrefix*" -or $groupName -like "$rolePrefix*" -or ($groupName -like "$appPrefix*" -and $groupName -eq 'SG-APP-Salesforce')) {
        if ($newGroups -notcontains $groupName -and $groupMap.ContainsKey($groupName)) {
            Remove-LabGroupMember -GroupId $groupMap[$groupName] -UserId $user.Id -GroupName $groupName -UserPrincipalName $UserPrincipalName
        }
    }
}

foreach ($groupName in $newGroups) {
    if ($groupMap.ContainsKey($groupName)) {
        Add-LabGroupMember -GroupId $groupMap[$groupName] -UserId $user.Id -GroupName $groupName -UserPrincipalName $UserPrincipalName
    }
}

Write-LabLog "Mover workflow complete: $UserPrincipalName moved from $oldDept to $NewDepartment" 'SUCCESS'
