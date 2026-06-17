#Requires -Version 7.0
<#
.SYNOPSIS
    Verify Phase 5 JML automation scripts and safeguards against the live tenant.
.DESCRIPTION
    Non-destructive checks: script presence, group-resolution rules, break-glass leaver refusal.
    Full Joiner/Mover/Leaver lifecycle is operator-run — see docs/jml/joiner-mover-leaver.md.
.EXAMPLE
    .\Verify-LabJml.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

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

Write-LabLog 'Verifying JML automation...' 'INFO'

foreach ($scriptName in @('Invoke-Joiner.ps1', 'Invoke-Mover.ps1', 'Invoke-Leaver.ps1')) {
    $path = Join-Path $PSScriptRoot $scriptName
    Assert-Check (Test-Path $path) "$scriptName present"
}

$groupsPath = Get-LabConfigPath 'groups.definition.json'
$groupConfig = Get-Content $groupsPath -Raw | ConvertFrom-Json
$rules = $groupConfig.membershipRules
$sampleUser = [pscustomobject]@{
    userPrincipalName = 'sample@lab.local'
    department        = 'Engineering'
    roleTier          = 'Employee'
    status            = 'Active'
    isBreakGlass      = $false
}
$resolved = Resolve-LabGroupNamesForUser -User $sampleUser -Rules $rules
foreach ($expected in @('SG-DEPT-Engineering', 'SG-ROLE-Employee', 'SG-APP-Microsoft365', 'SG-LIC-M365-E3')) {
    Assert-Check ($resolved -contains $expected) "Resolve-LabGroupNamesForUser includes $expected"
}

$domain = (Get-LabEnv).DOMAIN
$breakGlassUpn = "adm-breakglass@$domain"
try {
    & (Join-Path $PSScriptRoot 'Invoke-Leaver.ps1') -UserPrincipalName $breakGlassUpn
    Assert-Check $false 'Leaver must refuse break-glass offboard'
}
catch {
    Assert-Check ($_.Exception.Message -match 'Refusing to offboard break-glass') 'Leaver refuses break-glass offboard'
}

if ($failures -eq 0) {
    Write-LabLog 'All JML automation checks passed.' 'SUCCESS'
    exit 0
}

Write-LabLog "$failures check(s) failed." 'ERROR'
exit 1
