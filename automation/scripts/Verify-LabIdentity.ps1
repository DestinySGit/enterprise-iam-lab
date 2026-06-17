#Requires -Version 7.0
<#
.SYNOPSIS
    Verify Phase 2 identity foundation against the live tenant.
.EXAMPLE
    .\Verify-LabIdentity.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

$groupsPath = Get-LabConfigPath 'groups.definition.json'
$usersPath = Get-LabConfigPath 'users.seed.json'
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json
$seed = Get-Content $usersPath -Raw | ConvertFrom-Json
$domain = (Get-LabEnv).DOMAIN

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

Write-LabLog 'Verifying identity foundation...' 'INFO'

$expectedGroupCount = $groupConfig.groups.Count
$labGroups = Get-MgGroup -Filter "startswith(displayName,'SG-')" -All -Property Id, DisplayName
Assert-Check ($labGroups.Count -ge $expectedGroupCount) "Security groups: $($labGroups.Count) (expected $expectedGroupCount)"

$licGroup = $labGroups | Where-Object { $_.DisplayName -eq 'SG-LIC-M365-E3' }
Assert-Check ($null -ne $licGroup) 'Group SG-LIC-M365-E3 exists'

$seedUpns = @($seed.users | ForEach-Object { Resolve-LabUserUpn -UserPrincipalName $_.userPrincipalName })
$tenantUsers = Get-MgUser -All -Property Id, UserPrincipalName, Department
$seedUsers = @($tenantUsers | Where-Object { $_.UserPrincipalName -in $seedUpns })
Assert-Check ($seedUsers.Count -eq $seed.users.Count) "Seed users: $($seedUsers.Count) (expected $($seed.users.Count))"

$missingDept = @($seedUsers | Where-Object { [string]::IsNullOrWhiteSpace($_.Department) })
Assert-Check ($missingDept.Count -eq 0) "Department attribute populated on all seed users (missing: $($missingDept.Count))"

$managerChecks = 0
$managerFailures = 0
foreach ($user in $seed.users) {
    if (-not $user.managerUpn) { continue }
    $upn = Resolve-LabUserUpn -UserPrincipalName $user.userPrincipalName
    $mgrUpn = Resolve-LabUserUpn -UserPrincipalName $user.managerUpn
    $tenantUser = $seedUsers | Where-Object { $_.UserPrincipalName -eq $upn }
    if (-not $tenantUser) { continue }
    $managerChecks++
    try {
        $manager = Get-MgUserManager -UserId $tenantUser.Id -ErrorAction Stop
        if ($manager.AdditionalProperties.userPrincipalName -ne $mgrUpn) {
            $managerFailures++
        }
    }
    catch {
        $managerFailures++
    }
}
Assert-Check ($managerFailures -eq 0) "Manager relationships verified ($managerChecks users with managers)"

$groupMap = @{}
foreach ($g in $labGroups) { $groupMap[$g.DisplayName] = $g.Id }

foreach ($deptGroup in ($groupConfig.groups | Where-Object { $_.groupType -eq 'Department' })) {
    $expected = @($seed.users | Where-Object { "SG-DEPT-$($_.department)" -eq $deptGroup.displayName }).Count
    if ($expected -eq 0) { continue }
    if (-not $groupMap.ContainsKey($deptGroup.displayName)) { continue }
    $members = Get-MgGroupMember -GroupId $groupMap[$deptGroup.displayName] -All
    $memberUsers = @($members | Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user' })
    Assert-Check ($memberUsers.Count -eq $expected) "$($deptGroup.displayName) members: $($memberUsers.Count) (expected $expected)"
}

$breakGlassUpn = "adm-breakglass@$domain"
$breakGlass = $seedUsers | Where-Object { $_.UserPrincipalName -eq $breakGlassUpn }
if ($breakGlass -and $groupMap.ContainsKey('SG-EXCLUDE-BreakGlass')) {
    $bgMembers = Get-MgGroupMember -GroupId $groupMap['SG-EXCLUDE-BreakGlass'] -All
    $inGroup = @($bgMembers | Where-Object { $_.Id -eq $breakGlass.Id }).Count -gt 0
    Assert-Check $inGroup 'adm-breakglass is member of SG-EXCLUDE-BreakGlass'
}

if ($failures -eq 0) {
    Write-LabLog 'All identity foundation checks passed.' 'SUCCESS'
    exit 0
}

Write-LabLog "$failures check(s) failed." 'ERROR'
exit 1
