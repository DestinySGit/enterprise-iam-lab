#Requires -Version 7.0
<#
.SYNOPSIS
    Verify Phase 6 access governance scripts, review scope, and report outputs.
.DESCRIPTION
    Non-destructive checks against the live tenant. On Entra ID Free tenants,
    validates scripted reports and group owners; portal access review campaigns
    are documented only (requires P2).
.EXAMPLE
    .\Verify-LabAccessGovernance.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

$failures = 0
$warnings = 0

function Assert-Check {
    param(
        [bool]$Condition,
        [string]$Message,
        [ValidateSet('ERROR', 'WARN')]
        [string]$OnFailure = 'ERROR'
    )
    if ($Condition) {
        Write-LabLog $Message 'SUCCESS'
    }
    elseif ($OnFailure -eq 'WARN') {
        Write-LabLog $Message 'WARN'
        $script:warnings++
    }
    else {
        Write-LabLog $Message 'ERROR'
        $script:failures++
    }
}

Write-LabLog 'Verifying access governance (review scope, reports, procedures)...' 'INFO'

foreach ($scriptName in @('Get-InactiveUsers.ps1', 'Export-RbacMatrix.ps1', 'Set-LabGroupOwners.ps1')) {
    $path = Join-Path $PSScriptRoot $scriptName
    Assert-Check (Test-Path $path) "$scriptName present"
}

$quarterlyDoc = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'docs\access-governance\quarterly-review.md'
Assert-Check (Test-Path $quarterlyDoc) 'quarterly-review.md procedure doc present'

$configPath = Get-LabConfigPath 'groups.definition.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
Assert-Check ($null -ne $config.accessReviewScope) 'accessReviewScope defined in groups.definition.json'

$scopeGroups = @($config.accessReviewScope.groups)
Assert-Check ($scopeGroups.Count -ge 4) "accessReviewScope defines $($scopeGroups.Count) review groups (minimum 4)"

$groupMap = Get-LabGroupMap
foreach ($scopeGroup in $scopeGroups) {
    $groupName = $scopeGroup.displayName
    Assert-Check $groupMap.ContainsKey($groupName) "$groupName exists in tenant"

    $ownerUpn = Resolve-LabUserUpn -UserPrincipalName $scopeGroup.ownerUpn
    $owner = Get-LabUserByUpn -UserPrincipalName $ownerUpn
    Assert-Check ($null -ne $owner) "Owner user $ownerUpn exists for $groupName"

    if ($groupMap.ContainsKey($groupName) -and $owner) {
        $groupId = $groupMap[$groupName]
        $owners = @(Get-MgGroupOwner -GroupId $groupId -All)
        $hasOwner = @($owners | Where-Object { $_.Id -eq $owner.Id }).Count -gt 0
        Assert-Check $hasOwner "$groupName has configured owner $ownerUpn" -OnFailure 'WARN'
    }
}

$reportsRoot = Split-Path (Get-LabReportsPath 'probe.csv') -Parent
$sampleInactivePath = Join-Path $reportsRoot 'samples\inactive-users-sample.csv'
if (Test-Path $sampleInactivePath) {
    $sampleHeaders = @((Import-Csv $sampleInactivePath | Get-Member -MemberType NoteProperty).Name)
    foreach ($expected in @('DisplayName', 'UserPrincipalName', 'RecommendedAction')) {
        Assert-Check ($sampleHeaders -contains $expected) "inactive-users sample includes $expected column"
    }
}

$sampleCertPath = Join-Path $reportsRoot 'samples\access-certification-sample.csv'
if (Test-Path $sampleCertPath) {
    $certHeaders = @((Import-Csv $sampleCertPath | Get-Member -MemberType NoteProperty).Name)
    foreach ($expected in @('UserPrincipalName', 'Resource', 'Decision', 'Reviewer')) {
        Assert-Check ($certHeaders -contains $expected) "access-certification sample includes $expected column"
    }
}

try {
    Get-MgIdentityGovernanceAccessReviewDefinition -Top 1 -ErrorAction Stop | Out-Null
    Assert-Check $true 'Access review definitions readable (Entra ID P2 available)'
}
catch {
    $message = $_.Exception.Message
    if ($message -match 'NonPremium|premium|Forbidden|403|unauthorized|Unauthorized') {
        Write-LabLog 'No Entra ID P2 — portal access review campaigns documented only' 'WARN'
        $script:warnings++
    }
    else {
        Assert-Check $false "Access review API check failed: $message"
    }
}

$rbacOutput = Join-Path $env:TEMP "rbac-matrix-verify-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
try {
    & (Join-Path $PSScriptRoot 'Export-RbacMatrix.ps1') -OutputPath $rbacOutput | Out-Null
    $rbacRows = @(Import-Csv $rbacOutput)
    Assert-Check ($rbacRows.Count -gt 0) "Export-RbacMatrix.ps1 produced $($rbacRows.Count) rows"
}
finally {
    if (Test-Path $rbacOutput) { Remove-Item $rbacOutput -Force }
}

$inactiveOutput = Join-Path $env:TEMP "inactive-users-verify-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
try {
    & (Join-Path $PSScriptRoot 'Get-InactiveUsers.ps1') -InactiveDays 90 -OutputPath $inactiveOutput | Out-Null
    Assert-Check (Test-Path $inactiveOutput) 'Get-InactiveUsers.ps1 completed without error'
    $inactiveRows = @(Import-Csv $inactiveOutput -ErrorAction SilentlyContinue)
    if ($inactiveRows.Count -gt 0) {
        $inactiveHeaders = @($inactiveRows[0].PSObject.Properties.Name)
        Assert-Check ($inactiveHeaders -contains 'DataSource') 'Get-InactiveUsers.ps1 includes DataSource column'
    }
    else {
        $headerLine = Get-Content $inactiveOutput -TotalCount 1 -ErrorAction SilentlyContinue
        Assert-Check ([bool]($headerLine -match 'DataSource')) 'Get-InactiveUsers.ps1 CSV header includes DataSource column'
    }
}
finally {
    if (Test-Path $inactiveOutput) { Remove-Item $inactiveOutput -Force }
}

if ($failures -eq 0) {
    if ($warnings -gt 0) {
        Write-LabLog "Access governance checks passed with $warnings warning(s)." 'SUCCESS'
    }
    else {
        Write-LabLog 'All access governance checks passed.' 'SUCCESS'
    }
    exit 0
}

Write-LabLog "$failures check(s) failed." 'ERROR'
exit 1
