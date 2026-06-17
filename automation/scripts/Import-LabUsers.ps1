#Requires -Version 7.0
<#
.SYNOPSIS
    Seed lab users and group memberships from users.seed.json.
.PARAMETER Password
    Temporary password for new users. Must meet tenant password policy.
.EXAMPLE
    .\Import-LabUsers.ps1 -Password 'ChangeMe!2026Lab'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Password
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}
Test-LabGraphScopes -RequiredScopes @('User.ReadWrite.All', 'Group.ReadWrite.All') -FailOnMissing

$usersPath = Get-LabConfigPath 'users.seed.json'
$groupsPath = Get-LabConfigPath 'groups.definition.json'
$seed = Get-Content $usersPath -Raw | ConvertFrom-Json
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json
$rules = $groupConfig.membershipRules

$groupMap = Get-LabGroupMap
$createdUsers = @{}

Write-LabLog "Importing $($seed.users.Count) users (domain: $(Get-LabDomain))" 'INFO'

foreach ($user in $seed.users) {
    $upn = Resolve-LabUserUpn -UserPrincipalName $user.userPrincipalName
    $existing = Get-LabUserByUpn -UserPrincipalName $upn
    if ($existing) {
        Write-LabLog "$upn already exists — skipping create" 'WARN'
        $createdUsers[$upn] = $existing.Id
        continue
    }

    $passwordProfile = @{
        Password                      = $Password
        ForceChangePasswordNextSignIn = $false
    }

    $params = @{
        AccountEnabled      = $true
        DisplayName         = $user.displayName
        GivenName           = $user.givenName
        Surname             = $user.surname
        MailNickname        = $user.mailNickname
        UserPrincipalName   = $upn
        Department          = $user.department
        JobTitle            = $user.jobTitle
        PasswordProfile     = $passwordProfile
        UsageLocation       = 'US'
    }

    $newUser = Invoke-GraphWithRetry { New-MgUser @params -ErrorAction Stop }
    if (-not $newUser -or [string]::IsNullOrWhiteSpace($newUser.Id)) {
        throw "Failed to create $upn. Verify User.ReadWrite.All is granted with admin consent."
    }
    $createdUsers[$upn] = $newUser.Id
    Write-LabLog "Created $upn" 'SUCCESS'
}

Write-LabLog 'Setting manager relationships (pass 2)...' 'INFO'
foreach ($user in $seed.users) {
    if (-not $user.managerUpn) { continue }
    $upn = Resolve-LabUserUpn -UserPrincipalName $user.userPrincipalName
    $mgrUpn = Resolve-LabUserUpn -UserPrincipalName $user.managerUpn
    if (-not $createdUsers.ContainsKey($upn)) {
        $u = Get-LabUserByUpn -UserPrincipalName $upn
        $createdUsers[$upn] = $u.Id
    }
    if (-not $createdUsers.ContainsKey($mgrUpn)) {
        $mgr = Get-LabUserByUpn -UserPrincipalName $mgrUpn
        if ($mgr) { $createdUsers[$mgrUpn] = $mgr.Id }
    }
    $userId = $createdUsers[$upn]
    if ([string]::IsNullOrWhiteSpace($userId)) {
        Write-LabLog "Cannot set manager for $upn — user ID not found" 'ERROR'
        continue
    }
    if ($createdUsers.ContainsKey($mgrUpn)) {
        Invoke-GraphWithRetry {
            Set-MgUserManagerByRef -UserId $userId -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/users/$($createdUsers[$mgrUpn])" } -ErrorAction Stop
        }
        Write-LabLog "Set manager for $upn -> $mgrUpn" 'INFO'
    }
}

Write-LabLog 'Assigning group memberships (pass 3)...' 'INFO'
foreach ($user in $seed.users) {
    $upn = Resolve-LabUserUpn -UserPrincipalName $user.userPrincipalName
    $userId = $createdUsers[$upn]
    if (-not $userId) {
        $u = Get-LabUserByUpn -UserPrincipalName $upn
        $userId = $u.Id
    }
    $targetGroups = Resolve-LabGroupNamesForUser -User $user -Rules $rules
    foreach ($groupName in $targetGroups) {
        if (-not $groupMap.ContainsKey($groupName)) {
            Write-LabLog "Group $groupName not found — run Import-LabGroups.ps1 first" 'ERROR'
            continue
        }
        Add-LabGroupMember -GroupId $groupMap[$groupName] -UserId $userId -GroupName $groupName -UserPrincipalName $upn
    }
}

Write-LabLog 'User import complete.' 'SUCCESS'
