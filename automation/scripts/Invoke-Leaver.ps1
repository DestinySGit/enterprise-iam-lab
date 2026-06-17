#Requires -Version 7.0
<#
.SYNOPSIS
    Leaver workflow — disable account, revoke sessions, remove group memberships.
.PARAMETER UserPrincipalName
.PARAMETER RemoveLicenses
.EXAMPLE
    .\Invoke-Leaver.ps1 -UserPrincipalName 'james.anderson@northwindcollab.onmicrosoft.com'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$UserPrincipalName,
    [switch]$RemoveLicenses
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$user = Get-LabUserByUpn -UserPrincipalName $UserPrincipalName
if (-not $user) { throw "User $UserPrincipalName not found." }

if ($UserPrincipalName -like 'adm-breakglass@*') {
    throw 'Refusing to offboard break-glass account.'
}

if (-not $user.AccountEnabled) {
    Write-LabLog "$UserPrincipalName already disabled — continuing cleanup" 'WARN'
}
else {
    Invoke-GraphWithRetry { Update-MgUser -UserId $user.Id -AccountEnabled:$false }
    Write-LabLog "Disabled account $UserPrincipalName" 'SUCCESS'
}

Invoke-GraphWithRetry { Revoke-MgUserSignInSession -UserId $user.Id }
Write-LabLog 'Revoked sign-in sessions' 'INFO'

$memberships = Invoke-GraphWithRetry { Get-MgUserMemberOf -UserId $user.Id -All }
foreach ($member in $memberships) {
    if ($member.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group') {
        Remove-LabGroupMember -GroupId $member.Id -UserId $user.Id -GroupName $member.AdditionalProperties.displayName -UserPrincipalName $UserPrincipalName
    }
}

if ($RemoveLicenses) {
    $licenses = Invoke-GraphWithRetry { Get-MgUserLicenseDetail -UserId $user.Id }
    if ($licenses) {
        $skuIds = $licenses | ForEach-Object { $_.SkuId }
        Invoke-GraphWithRetry {
            Set-MgUserLicense -UserId $user.Id -AddLicenses @() -RemoveLicenses $skuIds
        }
        Write-LabLog 'Removed license assignments' 'INFO'
    }
}
else {
    Write-LabLog 'License reclamation skipped — pass -RemoveLicenses to reclaim SKUs' 'INFO'
}

Write-LabLog "Leaver workflow complete for $UserPrincipalName" 'SUCCESS'
