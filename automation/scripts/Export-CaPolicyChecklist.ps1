#Requires -Version 7.0
<#
.SYNOPSIS
    Export a portal rollout checklist from ca-policies.spec.json.
.DESCRIPTION
    Produces a CSV for manual Conditional Access configuration in Entra admin center.
    Use when the tenant has Entra ID P1+ licensing.
.EXAMPLE
    .\Export-CaPolicyChecklist.ps1
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$caSpecPath = Get-LabConfigPath 'ca-policies.spec.json'
$caSpec = Get-Content $caSpecPath -Raw | ConvertFrom-Json

if (-not $OutputPath) {
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Get-LabReportsPath "ca-policy-checklist-$timestamp.csv"
}

$rows = foreach ($policy in $caSpec.policies) {
    $grant = if ($policy.grantControls.builtInControls) {
        ($policy.grantControls.builtInControls -join ', ')
    } else { '' }

    $session = if ($policy.sessionControls.signInFrequency) {
        "$($policy.sessionControls.signInFrequency.value) $($policy.sessionControls.signInFrequency.type)"
    } else { '' }

    $excludeGroups = if ($policy.conditions.excludeGroups) {
        ($policy.conditions.excludeGroups -join '; ')
    } else { $caSpec.excludeGroup }

    [pscustomobject]@{
        PolicyName          = $policy.name
        InitialState        = $policy.state
        Description         = $policy.description
        ExcludeGroups       = $excludeGroups
        GrantControls       = $grant
        SessionControls     = $session
        EnableAfterValidation = $policy.enableAfterValidation
        Rationale           = $policy.rationale
        PortalConfigured    = ''
        Notes               = ''
    }
}

$rows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-LabLog "CA policy checklist exported to $OutputPath" 'SUCCESS'
Write-LabLog "Rollout: $($caSpec.rolloutStrategy)" 'INFO'
foreach ($step in $caSpec.portalSteps) {
    Write-LabLog "  - $step" 'INFO'
}

return $OutputPath
