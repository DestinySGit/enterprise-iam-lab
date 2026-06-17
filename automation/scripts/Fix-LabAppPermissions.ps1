#Requires -Version 7.0
<#
.SYNOPSIS
    Add missing Microsoft Graph application permissions and grant admin consent.
.DESCRIPTION
    Run interactively as Global Administrator when Connect-LabTenant.ps1 reports
    missing User.ReadWrite.All or other application permissions.
.EXAMPLE
    .\Fix-LabAppPermissions.ps1
#>
[CmdletBinding()]
param(
    [switch]$UseDeviceCode
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

$graphResourceId = '00000003-0000-0000-c000-000000000000'
$requiredRoles = Get-LabRequiredAppRoleIds

$labEnv = Get-LabEnv
$clientId = $labEnv.CLIENT_ID

Write-LabLog 'Connecting with delegated admin rights (browser sign-in required)...' 'INFO'
$connectParams = @{
    Scopes    = 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'RoleManagement.ReadWrite.Directory'
    NoWelcome = $true
}
if ($UseDeviceCode) {
    $connectParams.UseDeviceAuthentication = $true
    Write-LabLog 'Using device code flow — open https://microsoft.com/devicelogin when prompted.' 'INFO'
}
Connect-MgGraph @connectParams

$app = Get-MgApplication -Filter "appId eq '$clientId'" -Property Id, DisplayName, RequiredResourceAccess
if (-not $app) {
    throw "App registration not found for client ID $clientId"
}

Write-LabLog "Updating app: $($app.DisplayName)" 'INFO'
$graphAccess = $app.RequiredResourceAccess | Where-Object { $_.ResourceAppId -eq $graphResourceId }
if (-not $graphAccess) {
    $graphAccess = [Microsoft.Graph.PowerShell.Models.MicrosoftGraphRequiredResourceAccess]@{
        ResourceAppId  = $graphResourceId
        ResourceAccess = @()
    }
    $app.RequiredResourceAccess += $graphAccess
}

$desiredRoleIds = @($requiredRoles.Values | ForEach-Object { $_.ToLowerInvariant() } | Sort-Object -Unique)
$currentRoleIds = @(
    $graphAccess.ResourceAccess |
        Where-Object { $_.Type -eq 'Role' } |
        ForEach-Object { $_.Id.ToString().ToLowerInvariant() } |
        Sort-Object -Unique
)

if (($desiredRoleIds -join ',') -ne ($currentRoleIds -join ',')) {
    $graphAccess.ResourceAccess = @(
        foreach ($entry in $requiredRoles.GetEnumerator()) {
            [Microsoft.Graph.PowerShell.Models.MicrosoftGraphResourceAccess]@{
                Id   = $entry.Value
                Type = 'Role'
            }
        }
    )
    Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $app.RequiredResourceAccess
    Write-LabLog "Synced app registration permissions: $($requiredRoles.Keys -join ', ')" 'SUCCESS'
}
else {
    Write-LabLog 'All required application permissions already present on app registration.' 'INFO'
}

$sp = Get-MgServicePrincipal -Filter "appId eq '$clientId'"
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphResourceId'"
$existingAssignments = @(
    Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All |
        Where-Object { $_.ResourceId -eq $graphSp.Id }
)
$grantedRoleIds = @($existingAssignments | ForEach-Object { $_.AppRoleId.ToString().ToLowerInvariant() })

foreach ($entry in $requiredRoles.GetEnumerator()) {
    if ($grantedRoleIds -contains $entry.Value.ToLowerInvariant()) {
        Write-LabLog "Admin consent already granted for $($entry.Key)" 'INFO'
        continue
    }

    try {
        New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -BodyParameter @{
            principalId = $sp.Id
            resourceId  = $graphSp.Id
            appRoleId   = $entry.Value
        } -ErrorAction Stop | Out-Null
        Write-LabLog "Granted admin consent for $($entry.Key)" 'SUCCESS'
        $grantedRoleIds += $entry.Value.ToLowerInvariant()
    }
    catch {
        if ($_.Exception.Message -match 'already exists|Permission being assigned already exists') {
            Write-LabLog "Admin consent already granted for $($entry.Key)" 'INFO'
        }
        else {
            throw
        }
    }
}

Write-LabLog 'Permission fix complete. Re-run Connect-LabTenant.ps1 to verify scopes.' 'SUCCESS'
