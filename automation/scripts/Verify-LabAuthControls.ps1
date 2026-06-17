#Requires -Version 7.0
<#
.SYNOPSIS
    Verify Phase 4 auth controls against the live tenant and ca-policies.spec.json.
.DESCRIPTION
    On Entra ID Free tenants, validates Security defaults and break-glass exclusions.
    On P1+ tenants, also validates Conditional Access policies from the repo spec.
.EXAMPLE
    .\Verify-LabAuthControls.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

$caSpecPath = Get-LabConfigPath 'ca-policies.spec.json'
$caSpec = Get-Content $caSpecPath -Raw | ConvertFrom-Json
$domain = (Get-LabEnv).DOMAIN
$groupMap = Get-LabGroupMap

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

Write-LabLog 'Verifying auth controls (Security defaults, break-glass, Conditional Access)...' 'INFO'

$breakGlassGroupId = $groupMap['SG-EXCLUDE-BreakGlass']
Assert-Check ($null -ne $breakGlassGroupId) 'SG-EXCLUDE-BreakGlass exists'

$reportOnlyGroupId = $groupMap['SG-EXCLUDE-CA-ReportOnly']
Assert-Check ($null -ne $reportOnlyGroupId) 'SG-EXCLUDE-CA-ReportOnly exists'

$breakGlassUpn = "adm-breakglass@$domain"
$breakGlassUser = Get-LabUserByUpn -UserPrincipalName $breakGlassUpn
if ($breakGlassUser -and $breakGlassGroupId) {
    $bgMembers = Get-MgGroupMember -GroupId $breakGlassGroupId -All
    $inGroup = @($bgMembers | Where-Object { $_.Id -eq $breakGlassUser.Id }).Count -gt 0
    Assert-Check $inGroup 'adm-breakglass is member of SG-EXCLUDE-BreakGlass'
}

try {
    $securityDefaults = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy -ErrorAction Stop
    Assert-Check $securityDefaults.IsEnabled 'Security defaults are enabled (Entra Free MFA baseline)'
}
catch {
    Assert-Check $false "Security defaults readable via Graph: $($_.Exception.Message)"
}

$tenantPolicies = @()
try {
    $tenantPolicies = @(Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop)
}
catch {
    Write-LabLog "Conditional Access policies not readable: $($_.Exception.Message)" 'WARN'
    $warnings++
}

if ($tenantPolicies.Count -eq 0) {
    Assert-Check $true 'No custom CA policies in tenant (expected on Entra ID Free)' -OnFailure 'WARN'
    Write-LabLog 'CA policy specs are in automation/config/ca-policies.spec.json — deploy manually when P1+ is available.' 'INFO'
}
else {
    Write-LabLog "Found $($tenantPolicies.Count) Conditional Access policy(ies) in tenant." 'INFO'

    foreach ($specPolicy in $caSpec.policies) {
        $livePolicy = $tenantPolicies | Where-Object { $_.DisplayName -eq $specPolicy.name } | Select-Object -First 1
        if (-not $livePolicy) {
            Assert-Check $false "CA policy '$($specPolicy.name)' exists in tenant"
            continue
        }

        Assert-Check $true "CA policy '$($specPolicy.name)' exists (state: $($livePolicy.State))"

        if ($breakGlassGroupId) {
            $excludedGroups = @($livePolicy.Conditions.Users.ExcludeGroups)
            $excludesBreakGlass = $excludedGroups -contains $breakGlassGroupId
            Assert-Check $excludesBreakGlass "$($specPolicy.name) excludes SG-EXCLUDE-BreakGlass"
        }
    }

    $unexpectedPolicies = @($tenantPolicies | Where-Object {
        $_.DisplayName -notin @($caSpec.policies | ForEach-Object { $_.name })
    })
    if ($unexpectedPolicies.Count -gt 0) {
        Write-LabLog "Additional CA policies not in spec: $($unexpectedPolicies.DisplayName -join ', ')" 'WARN'
        $warnings++
    }
}

$expectedPolicyCount = @($caSpec.policies).Count
Assert-Check ($caSpec.excludeGroup -eq 'SG-EXCLUDE-BreakGlass') 'ca-policies.spec.json excludeGroup is SG-EXCLUDE-BreakGlass'
Assert-Check ($expectedPolicyCount -ge 3) "ca-policies.spec.json defines $expectedPolicyCount policies (minimum 3)"

if ($failures -eq 0) {
    if ($warnings -gt 0) {
        Write-LabLog "Auth control checks passed with $warnings warning(s)." 'SUCCESS'
    }
    else {
        Write-LabLog 'All auth control checks passed.' 'SUCCESS'
    }
    exit 0
}

Write-LabLog "$failures check(s) failed." 'ERROR'
exit 1
