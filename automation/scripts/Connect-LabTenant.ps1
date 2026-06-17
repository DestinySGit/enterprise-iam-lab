#Requires -Version 7.0
<#
.SYNOPSIS
    Connect to the Northwind lab tenant using certificate-based app registration auth.
.EXAMPLE
    .\Connect-LabTenant.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'LabIdentity.psm1') -Force

$requiredModules = @(
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Users',
    'Microsoft.Graph.Groups',
    'Microsoft.Graph.Identity.SignIns',
    'Microsoft.Graph.Identity.Governance'
)

foreach ($mod in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-LabLog "Installing $mod..." 'INFO'
        Install-Module $mod -Scope CurrentUser -Force -AllowClobber
    }
    Import-Module $mod -ErrorAction Stop
}

$env = Get-LabEnv
$tenantId = $env.TENANT_ID
$clientId = $env.CLIENT_ID
$thumbprint = $env.CERT_THUMBPRINT

Write-LabLog "Connecting to tenant $tenantId as app $clientId" 'INFO'

if (Get-MgContext) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}

Connect-MgGraph -ClientId $clientId -TenantId $tenantId -CertificateThumbprint $thumbprint -NoWelcome

$context = Get-MgContext
if (-not $context) {
    throw 'Failed to establish Graph context.'
}

Write-LabLog "Connected successfully. Scopes: $($context.Scopes -join ', ')" 'SUCCESS'
Test-LabGraphScopes
