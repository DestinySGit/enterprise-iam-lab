#Requires -Version 7.0
<#
.SYNOPSIS
    Create security groups defined in groups.definition.json.
.EXAMPLE
    .\Import-LabGroups.ps1
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

Write-LabLog "Importing $($config.groups.Count) groups from $configPath" 'INFO'

foreach ($group in $config.groups) {
    $existing = Get-MgGroup -Filter "displayName eq '$($group.displayName)'" -ErrorAction SilentlyContinue
    if ($existing) {
        Write-LabLog "Group $($group.displayName) already exists — skipping" 'WARN'
        continue
    }

    $params = @{
        DisplayName     = $group.displayName
        Description     = $group.description
        MailEnabled     = [bool]$group.mailEnabled
        SecurityEnabled = [bool]$group.securityEnabled
        MailNickname    = ($group.displayName -replace '[^a-zA-Z0-9]', '')
    }
    if ($group.PSObject.Properties.Name -contains 'isAssignableToRole') {
        $params.IsAssignableToRole = [bool]$group.isAssignableToRole
    }

    try {
        Invoke-GraphWithRetry {
            New-MgGroup @params -ErrorAction Stop | Out-Null
        }
    }
    catch {
        if ($params.ContainsKey('IsAssignableToRole') -and $_.Exception.Message -match 'AAD Premium|Premium') {
            Write-LabLog "Entra Free: creating $($group.displayName) without role-assignable flag" 'WARN'
            $params.Remove('IsAssignableToRole')
            Invoke-GraphWithRetry {
                New-MgGroup @params -ErrorAction Stop | Out-Null
            }
        }
        else {
            throw
        }
    }
    Write-LabLog "Created group $($group.displayName)" 'SUCCESS'
}

Write-LabLog 'Group import complete.' 'SUCCESS'
