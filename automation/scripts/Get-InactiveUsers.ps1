#Requires -Version 7.0
<#
.SYNOPSIS
    Export users with no sign-in activity in the last N days.
.PARAMETER InactiveDays
    Default 90.
.PARAMETER OutputPath
.EXAMPLE
    .\Get-InactiveUsers.ps1 -InactiveDays 90
.NOTES
    SignInActivity requires Entra ID P1/P2. On Free tenants, falls back to
    lastPasswordChangeDateTime as an inactivity proxy (see quarterly-review.md).
#>
[CmdletBinding()]
param(
    [int]$InactiveDays = 90,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

if (-not (Get-MgContext)) {
    & (Join-Path $PSScriptRoot 'Connect-LabTenant.ps1') | Out-Null
}

if (-not $OutputPath) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Get-LabReportsPath "inactive-users-$stamp.csv"
}

$cutoff = (Get-Date).AddDays(-1 * $InactiveDays)
$cutoffIso = $cutoff.ToUniversalTime().ToString('o')
Write-LabLog "Finding users inactive since $cutoffIso ($InactiveDays days)" 'INFO'

$dataSource = 'PasswordChangeProxy'
$userProperties = @(
    'Id', 'DisplayName', 'UserPrincipalName', 'Department', 'AccountEnabled',
    'LastPasswordChangeDateTime', 'CreatedDateTime'
)

try {
    Get-MgUser -Top 1 -Property SignInActivity -ErrorAction Stop | Out-Null
    $dataSource = 'SignInActivity'
    $userProperties = @(
        'Id', 'DisplayName', 'UserPrincipalName', 'Department', 'AccountEnabled', 'SignInActivity'
    )
}
catch {
    if ($_.Exception.Message -notmatch 'NonPremium|premium|P1|P2') {
        throw
    }
    Write-LabLog 'SignInActivity requires Entra ID P1/P2 — using lastPasswordChangeDateTime proxy' 'WARN'
}

$users = Get-MgUser -All -Property $userProperties -ErrorAction Stop

$inactive = @()

foreach ($user in $users) {
    if ($user.UserPrincipalName -like 'adm-breakglass@*') { continue }

    $lastActivity = $null
    if ($dataSource -eq 'SignInActivity') {
        $lastActivity = $user.SignInActivity.LastSignInDateTime
    }
    else {
        $lastActivity = if ($user.LastPasswordChangeDateTime) {
            $user.LastPasswordChangeDateTime
        }
        else {
            $user.CreatedDateTime
        }
    }

    if (-not $lastActivity -or [datetime]$lastActivity -lt $cutoff) {
        $inactiveDaysValue = if ($lastActivity) {
            [int]((Get-Date) - [datetime]$lastActivity).TotalDays
        }
        else {
            'Never'
        }

        $inactive += [pscustomobject]@{
            DisplayName       = $user.DisplayName
            UserPrincipalName = $user.UserPrincipalName
            Department        = $user.Department
            AccountEnabled    = $user.AccountEnabled
            LastSignIn        = $lastActivity
            InactiveDays      = $inactiveDaysValue
            DataSource        = $dataSource
            RecommendedAction = if ($user.AccountEnabled) { 'Review for disable' } else { 'Already disabled' }
        }
    }
}

$inactive | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
if ($inactive.Count -eq 0) {
    $header = 'DisplayName,UserPrincipalName,Department,AccountEnabled,LastSignIn,InactiveDays,DataSource,RecommendedAction'
    Set-Content -Path $OutputPath -Value $header -Encoding utf8NoBOM
}
Write-LabLog "Exported $($inactive.Count) inactive users to $OutputPath (source: $dataSource)" 'SUCCESS'
$inactive | Format-Table -AutoSize
