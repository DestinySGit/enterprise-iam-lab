# LabIdentity.psm1 — shared helpers for Northwind Collaborative IAM lab

function Get-LabConfigPath {
    param([string]$FileName)
    $configRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'config'
    Join-Path $configRoot $FileName
}

function Get-LabEnv {
    $envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
    if (-not (Test-Path $envPath)) {
        throw "Missing automation/.env file. Copy .env.example and fill in tenant values."
    }
    $values = @{}
    Get-Content $envPath | ForEach-Object {
        if ($_ -match '^\s*#' -or $_ -notmatch '=') { return }
        $parts = $_ -split '=', 2
        $values[$parts[0].Trim()] = $parts[1].Trim()
    }
    foreach ($key in @('TENANT_ID', 'CLIENT_ID', 'CERT_THUMBPRINT', 'DOMAIN')) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            throw "Missing required .env value: $key"
        }
    }
    return [pscustomobject]$values
}

function Write-LabLog {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO'
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp][$Level] $Message"
}

function Invoke-GraphWithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 5
    )
    $attempt = 0
    while ($true) {
        try {
            return & $ScriptBlock
        }
        catch {
            $attempt++
            $isThrottle = $_.Exception.Message -match 'Too Many Requests|429|throttl'
            if (-not $isThrottle -or $attempt -ge $MaxRetries) {
                throw
            }
            $delay = [math]::Pow(2, $attempt)
            Write-LabLog "Graph throttled — retry $attempt/$MaxRetries in ${delay}s" 'WARN'
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-LabGroupMap {
    $groups = Get-MgGroup -All -Property Id, DisplayName
    $map = @{}
    foreach ($g in $groups) { $map[$g.DisplayName] = $g.Id }
    return $map
}

function Get-LabUserByUpn {
    param([string]$UserPrincipalName)
    Get-MgUser -Filter "userPrincipalName eq '$UserPrincipalName'" -Property Id, UserPrincipalName, DisplayName, Department, AccountEnabled
}

function Add-LabGroupMember {
    param(
        [string]$GroupId,
        [string]$UserId,
        [string]$GroupName,
        [string]$UserPrincipalName
    )
    try {
        Invoke-GraphWithRetry {
            New-MgGroupMemberByRef -GroupId $GroupId -BodyParameter @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$UserId" } | Out-Null
        }
        Write-LabLog "Added $UserPrincipalName to $GroupName" 'SUCCESS'
    }
    catch {
        if ($_.Exception.Message -match 'One or more added object references already exist') {
            Write-LabLog "$UserPrincipalName already in $GroupName — skipping" 'WARN'
        }
        else { throw }
    }
}

function Remove-LabGroupMember {
    param(
        [string]$GroupId,
        [string]$UserId,
        [string]$GroupName,
        [string]$UserPrincipalName
    )
    try {
        Invoke-GraphWithRetry {
            Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId
        }
        Write-LabLog "Removed $UserPrincipalName from $GroupName" 'SUCCESS'
    }
    catch {
        if ($_.Exception.Message -match 'does not exist' -or $_.Exception.Message -match 'Not Found') {
            Write-LabLog "$UserPrincipalName not in $GroupName — skipping" 'WARN'
        }
        else { throw }
    }
}

function Get-LabReportsPath {
    param([string]$FileName)
    $reportsRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'reports'
    if (-not (Test-Path $reportsRoot)) {
        New-Item -ItemType Directory -Path $reportsRoot -Force | Out-Null
    }
    Join-Path $reportsRoot $FileName
}

$script:LabRequiredAppScopes = @(
    'User.ReadWrite.All'
    'Group.ReadWrite.All'
    'Directory.Read.All'
    'AuditLog.Read.All'
    'Policy.Read.All'
)

$script:LabRbacAppScopes = @(
    'User.ReadWrite.All'
    'Group.ReadWrite.All'
    'Directory.Read.All'
    'Application.ReadWrite.All'
    'AppRoleAssignment.ReadWrite.All'
    'RoleManagement.ReadWrite.Directory'
)

function Get-LabRbacAppScopes {
    return @($script:LabRbacAppScopes)
}

function Get-LabGraphAppRoleMap {
    if (-not (Get-Module -Name 'Microsoft.Graph.Applications')) {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
    }

    $graphResourceId = '00000003-0000-0000-c000-000000000000'
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphResourceId'"
    $map = @{}
    foreach ($role in $graphSp.AppRoles) {
        if ($role.IsEnabled -and ($role.AllowedMemberTypes -contains 'Application')) {
            $map[$role.Value] = $role.Id.ToString().ToLowerInvariant()
        }
    }
    return $map
}

function Get-LabRequiredAppRoleIds {
    param(
        [string[]]$PermissionNames = ($script:LabRequiredAppScopes + $script:LabRbacAppScopes | Select-Object -Unique)
    )

    $roleMap = Get-LabGraphAppRoleMap
    $result = @{}
    $missing = @()

    foreach ($name in $PermissionNames) {
        if ($roleMap.ContainsKey($name)) {
            $result[$name] = $roleMap[$name]
        }
        else {
            $missing += $name
        }
    }

    if ($missing.Count -gt 0) {
        throw "Microsoft Graph app roles not found for: $($missing -join ', ')"
    }

    return $result
}

function Test-LabGraphScopes {
    param(
        [string[]]$RequiredScopes = $script:LabRequiredAppScopes,
        [switch]$FailOnMissing
    )
    $context = Get-MgContext
    if (-not $context) {
        throw 'Not connected to Microsoft Graph. Run Connect-LabTenant.ps1 first.'
    }

    # Certificate app-only auth does not populate all permissions in Get-MgContext.Scopes.
    if ($context.AuthType -eq 'AppOnly') {
        return Test-LabAppRoleGrants -RequiredScopes $RequiredScopes -FailOnMissing:$FailOnMissing
    }

    $granted = @($context.Scopes)
    $missing = @($RequiredScopes | Where-Object { $_ -notin $granted })
    foreach ($scope in $RequiredScopes) {
        if ($scope -in $granted) {
            Write-LabLog "Scope granted: $scope" 'SUCCESS'
        }
    }
    foreach ($scope in $missing) {
        Write-LabLog "Scope missing: $scope" 'ERROR'
    }
    if ($missing.Count -gt 0) {
        $message = @(
            'Automation app is missing required application permissions.'
            "Missing: $($missing -join ', ')"
            'Fix: Entra ID > App registrations > Northwind-Lab-Automation > API permissions — add missing Application permissions and Grant admin consent.'
            'Or run Fix-LabAppPermissions.ps1 interactively as Global Administrator.'
        ) -join ' '
        if ($FailOnMissing) { throw $message }
        Write-LabLog $message 'WARN'
        return $false
    }
    return $true
}

function Test-LabAppRoleGrants {
    param(
        [string[]]$RequiredScopes,
        [switch]$FailOnMissing
    )

    if (-not (Get-Module -Name 'Microsoft.Graph.Applications')) {
        Import-Module Microsoft.Graph.Applications -ErrorAction Stop
    }

    $graphResourceId = '00000003-0000-0000-c000-000000000000'
    $clientId = (Get-LabEnv).CLIENT_ID
    $sp = Get-MgServicePrincipal -Filter "appId eq '$clientId'"
    $graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphResourceId'"

    $grantedRoleIds = @(
        Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -All |
            Where-Object { $_.ResourceId -eq $graphSp.Id } |
            ForEach-Object { $_.AppRoleId.ToString().ToLowerInvariant() }
    )

    $missing = @()
    $roleMap = Get-LabRequiredAppRoleIds -PermissionNames $RequiredScopes

    foreach ($scope in $RequiredScopes) {
        $roleId = $roleMap[$scope]
        if ($grantedRoleIds -contains $roleId.ToLowerInvariant()) {
            Write-LabLog "Permission granted: $scope" 'SUCCESS'
        }
        else {
            Write-LabLog "Permission missing: $scope" 'ERROR'
            $missing += $scope
        }
    }

    if ($missing.Count -gt 0) {
        $message = @(
            'Automation app is missing required application permissions.'
            "Missing: $($missing -join ', ')"
            'Fix: Entra ID > App registrations > Northwind-Lab-Automation > API permissions — add missing Application permissions and Grant admin consent.'
            'Or run Fix-LabAppPermissions.ps1 interactively as Global Administrator.'
        ) -join ' '
        if ($FailOnMissing) { throw $message }
        Write-LabLog $message 'WARN'
        return $false
    }
    return $true
}

function Get-LabDomain {
    (Get-LabEnv).DOMAIN
}

function Resolve-LabUserUpn {
    param([string]$UserPrincipalName)
    $domain = Get-LabDomain
    return ($UserPrincipalName -replace '@northwindcollab\.onmicrosoft\.com$', "@$domain")
}

function Resolve-LabIdentifierUri {
    param([string]$IdentifierUri)

    if ([string]::IsNullOrWhiteSpace($IdentifierUri)) {
        return $null
    }
    if ($IdentifierUri -match '^https?://') {
        $tenantId = (Get-LabEnv).TENANT_ID
        $slug = ($IdentifierUri -replace '^https?://', '' -replace '[^a-zA-Z0-9.-]', '-').Trim('-')
        return "api://$tenantId/$slug"
    }

    $tenantId = (Get-LabEnv).TENANT_ID
    $domain = Get-LabDomain
    $slug = ($IdentifierUri -replace '^api://', '').Trim('/')

    if ($IdentifierUri -match "^api://($([regex]::Escape($tenantId))|$([regex]::Escape($domain)))/") {
        return $IdentifierUri
    }

    return "api://$tenantId/$slug"
}

function Resolve-LabGroupNamesForUser {
    param(
        [pscustomobject]$User,
        [pscustomobject]$Rules
    )
    $groups = @()
    $deptGroup = ($Rules.departmentGroup -replace '\{department\}', $User.department)
    $groups += $deptGroup

    $roleKey = ($User.roleTier -replace ' ', '-')
    if ($roleKey -eq 'IT-Administrator') { $groups += 'SG-ROLE-IT-Administrator' }
    elseif ($roleKey -eq 'HR-Administrator') { $groups += 'SG-ROLE-HR-Administrator' }
    elseif ($User.roleTier -eq 'Manager') { $groups += 'SG-ROLE-Manager' }
    else { $groups += 'SG-ROLE-Employee' }

    $groups += $Rules.defaultAppGroups
    if ($Rules.salesforceDepartments -contains $User.department) {
        $groups += 'SG-APP-Salesforce'
    }
    if ($User.status -eq 'Active' -and -not $User.isBreakGlass) {
        $groups += $Rules.licenseGroup
    }
    if ($User.isBreakGlass) {
        $groups += 'SG-EXCLUDE-BreakGlass'
    }
    return $groups | Select-Object -Unique
}

Export-ModuleMember -Function @(
    'Get-LabConfigPath',
    'Get-LabEnv',
    'Write-LabLog',
    'Invoke-GraphWithRetry',
    'Get-LabGroupMap',
    'Get-LabUserByUpn',
    'Add-LabGroupMember',
    'Remove-LabGroupMember',
    'Get-LabReportsPath',
    'Get-LabDomain',
    'Resolve-LabUserUpn',
    'Resolve-LabIdentifierUri',
    'Get-LabRequiredAppRoleIds',
    'Get-LabRbacAppScopes',
    'Test-LabGraphScopes',
    'Resolve-LabGroupNamesForUser'
)
