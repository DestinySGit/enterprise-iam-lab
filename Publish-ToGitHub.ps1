#Requires -Version 7.0
<#
.SYNOPSIS
    Initialize git, validate safe files, commit, and push enterprise-iam-lab to GitHub.
.EXAMPLE
    .\Publish-ToGitHub.ps1 -GitHubUsername dstny
.EXAMPLE
    .\Publish-ToGitHub.ps1 -RemoteUrl https://github.com/dstny/enterprise-iam-lab.git
#>
[CmdletBinding()]
param(
    [string]$GitHubUsername,
    [string]$RemoteUrl,
    [string]$Branch = 'main',
    [switch]$SkipPush
)

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot

function Find-GitExecutable {
    $candidates = @(
        'git',
        "${env:ProgramFiles}\Git\cmd\git.exe",
        "${env:ProgramFiles}\Git\bin\git.exe",
        "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )
    foreach ($candidate in $candidates) {
        if ($candidate -eq 'git') {
            $cmd = Get-Command git -ErrorAction SilentlyContinue
            if ($cmd) { return $cmd.Source }
            continue
        }
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    & $script:GitExe @Args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$GitExe = Find-GitExecutable
if (-not $GitExe) {
    Write-Host 'Git is not installed. Install Git for Windows, then re-run this script:' -ForegroundColor Yellow
    Write-Host '  winget install --id Git.Git -e' -ForegroundColor Cyan
    Write-Host 'Or download: https://git-scm.com/download/win' -ForegroundColor Cyan
    exit 1
}

Write-Host "Using git: $GitExe" -ForegroundColor DarkGray

$blockedPatterns = @(
    'automation\.env$',
    'automation/automation\.env$',
    'automation/\.env$',
    '\.pfx$',
    '\.pem$',
    'vibe_coding-main/',
    'docs/enterprise-iam-lab/',
    '^reports/[^s].*\.csv$'
)

Push-Location $repoRoot
try {
    if (-not (Test-Path '.git')) {
        Write-Host 'Initializing git repository...' -ForegroundColor Cyan
        Invoke-Git init -b $Branch
    }

    Invoke-Git add .
    $staged = Invoke-Git diff --cached --name-only
    if (-not $staged) {
        Write-Host 'Nothing to commit.' -ForegroundColor Yellow
        exit 0
    }

    $violations = @()
    foreach ($file in $staged) {
        foreach ($pattern in $blockedPatterns) {
            if ($file -match $pattern) {
                $violations += $file
            }
        }
        if ($file -match '\.(env|pfx|pem)$' -and $file -notmatch '\.env\.example$') {
            $violations += $file
        }
    }

    if ($violations.Count -gt 0) {
        Write-Host 'Blocked files would be committed:' -ForegroundColor Red
        $violations | Sort-Object -Unique | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Invoke-Git reset
        throw 'Fix .gitignore or unstage secrets/internal docs before publishing.'
    }

    Write-Host "`nStaged files ($($staged.Count)):" -ForegroundColor Green
    $staged | ForEach-Object { Write-Host "  $_" }

    $hasCommit = $false
    try {
        Invoke-Git rev-parse HEAD | Out-Null
        $hasCommit = $true
    } catch {
        $hasCommit = $false
    }

    if ($hasCommit) {
        $status = Invoke-Git status --porcelain
        if (-not $status) {
            Write-Host 'Working tree clean — nothing new to commit.' -ForegroundColor Yellow
        } else {
            Invoke-Git commit -m 'Initial commit: Enterprise IAM Lab portfolio' -m 'Architecture, automation, runbooks, and redacted evidence for interview portfolio.'
        }
    } else {
        Invoke-Git commit -m 'Initial commit: Enterprise IAM Lab portfolio' -m 'Architecture, automation, runbooks, and redacted evidence for interview portfolio.'
    }

    if ($SkipPush) {
        Write-Host "`nCommit complete. Push skipped (-SkipPush)." -ForegroundColor Green
        return
    }

    if (-not $RemoteUrl) {
        if (-not $GitHubUsername) {
            $GitHubUsername = Read-Host 'GitHub username'
        }
        $RemoteUrl = "https://github.com/$GitHubUsername/enterprise-iam-lab.git"
    }

    $remotes = @(Invoke-Git remote)
    if ($remotes -contains 'origin') {
        Invoke-Git remote set-url origin $RemoteUrl
    } else {
        Invoke-Git remote add origin $RemoteUrl
    }

    Write-Host "`nPushing to $RemoteUrl ..." -ForegroundColor Cyan
    Write-Host 'Create the empty repo on GitHub first if it does not exist: https://github.com/new' -ForegroundColor DarkGray
    Invoke-Git push -u origin $Branch

    Write-Host "`nPublished successfully." -ForegroundColor Green
    Write-Host "Repo: $($RemoteUrl -replace '\.git$','')" -ForegroundColor Cyan
    Write-Host 'Suggested topics: identity, iam, microsoft-entra, conditional-access, rbac, powershell, microsoft-graph, access-governance' -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
