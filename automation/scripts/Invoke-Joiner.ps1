#Requires -Version 7.0
<#
.SYNOPSIS
    Joiner workflow — provision user and assign department, role, app, and license groups.
.PARAMETER UserPrincipalName
.PARAMETER DisplayName
.PARAMETER GivenName
.PARAMETER Surname
.PARAMETER Department
.PARAMETER JobTitle
.PARAMETER RoleTier
.PARAMETER ManagerUpn
.PARAMETER Password
.EXAMPLE
    .\Invoke-Joiner.ps1 -UserPrincipalName 'new.hire@northwindcollab.onmicrosoft.com' -DisplayName 'New Hire' -GivenName 'New' -Surname 'Hire' -Department 'Engineering' -JobTitle 'Software Engineer' -RoleTier 'Employee' -ManagerUpn 'lisa.diaz@northwindcollab.onmicrosoft.com' -Password 'ChangeMe!2026Lab'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UserPrincipalName,
    [Parameter(Mandatory = $true)][string]$DisplayName,
    [Parameter(Mandatory = $true)][string]$GivenName,
    [Parameter(Mandatory = $true)][string]$Surname,
    [Parameter(Mandatory = $true)][ValidateSet('HR', 'Finance', 'IT', 'Engineering', 'Operations')][string]$Department,
    [Parameter(Mandatory = $true)][string]$JobTitle,
    [Parameter(Mandatory = $true)][ValidateSet('Employee', 'Manager', 'IT Administrator', 'HR Administrator')][string]$RoleTier,
    [string]$ManagerUpn,
    [Parameter(Mandatory = $true)][string]$Password
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$groupsPath = Get-LabConfigPath 'groups.definition.json'
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json
$rules = $groupConfig.membershipRules
$groupMap = Get-LabGroupMap

$userObject = [pscustomobject]@{
    userPrincipalName = $UserPrincipalName
    department        = $Department
    roleTier          = $RoleTier
    status            = 'Active'
    isBreakGlass      = $false
}

$existing = Get-LabUserByUpn -UserPrincipalName $UserPrincipalName
if ($existing) {
    Write-LabLog "User $UserPrincipalName already exists (ALREADY_EXISTS)" 'WARN'
    $userId = $existing.Id
}
else {
    $mailNickname = ($UserPrincipalName -split '@')[0]
    $params = @{
        AccountEnabled    = $true
        DisplayName       = $DisplayName
        GivenName         = $GivenName
        Surname           = $Surname
        MailNickname      = $mailNickname
        UserPrincipalName = $UserPrincipalName
        Department        = $Department
        JobTitle          = $JobTitle
        PasswordProfile   = @{ Password = $Password; ForceChangePasswordNextSignIn = $true }
        UsageLocation     = 'US'
    }
    $newUser = Invoke-GraphWithRetry { New-MgUser @params }
    $userId = $newUser.Id
    Write-LabLog "Created user $UserPrincipalName" 'SUCCESS'
}

if ($ManagerUpn) {
    $manager = Get-LabUserByUpn -UserPrincipalName $ManagerUpn
    if (-not $manager) { throw "Manager $ManagerUpn not found." }
    Invoke-GraphWithRetry {
        Set-MgUserManagerByRef -UserId $userId -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($manager.Id)" }
    }
    Write-LabLog "Assigned manager $ManagerUpn" 'INFO'
}

$targetGroups = Resolve-LabGroupNamesForUser -User $userObject -Rules $rules
foreach ($groupName in $targetGroups) {
    if (-not $groupMap.ContainsKey($groupName)) { throw "Group $groupName not found." }
    Add-LabGroupMember -GroupId $groupMap[$groupName] -UserId $userId -GroupName $groupName -UserPrincipalName $UserPrincipalName
}

Write-LabLog "Joiner workflow complete for $UserPrincipalName" 'SUCCESS'
