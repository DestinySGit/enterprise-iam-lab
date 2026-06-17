#Requires -Version 7.0
<#
.SYNOPSIS
    Assign group owners for access review scope groups from groups.definition.json.
.DESCRIPTION
    Idempotent: skips groups that already have the configured owner assigned.
    Required before Entra ID access review campaigns (reviewer = group owners).
.EXAMPLE
    .\Set-LabGroupOwners.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

$configPath = Get-LabConfigPath 'groups.definition.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if (-not $config.accessReviewScope) {
    throw 'groups.definition.json is missing accessReviewScope configuration.'
}

$scopeGroups = @($config.accessReviewScope.groups)
Write-LabLog "Assigning owners for $($scopeGroups.Count) access review scope groups" 'INFO'

foreach ($scopeGroup in $scopeGroups) {
    $groupName = $scopeGroup.displayName
    $ownerUpn = Resolve-LabUserUpn -UserPrincipalName $scopeGroup.ownerUpn

    $group = Get-MgGroup -Filter "displayName eq '$groupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $group) {
        Write-LabLog "Group $groupName not found — run Import-LabGroups.ps1 first" 'ERROR'
        continue
    }

    $owner = Get-LabUserByUpn -UserPrincipalName $ownerUpn
    if (-not $owner) {
        Write-LabLog "Owner $ownerUpn not found for $groupName — run Import-LabUsers.ps1 first" 'ERROR'
        continue
    }

    $existingOwners = @(Get-MgGroupOwner -GroupId $group.Id -All)
    $alreadyOwner = @($existingOwners | Where-Object { $_.Id -eq $owner.Id }).Count -gt 0
    if ($alreadyOwner) {
        Write-LabLog "$groupName already owned by $ownerUpn — skipping" 'WARN'
        continue
    }

    Invoke-GraphWithRetry {
        New-MgGroupOwnerByRef -GroupId $group.Id -BodyParameter @{
            '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($owner.Id)"
        } -ErrorAction Stop | Out-Null
    }
    Write-LabLog "Assigned $ownerUpn as owner of $groupName" 'SUCCESS'
}

Write-LabLog 'Group owner assignment complete.' 'SUCCESS'
