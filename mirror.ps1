<#
.SYNOPSIS
    Publish a full snapshot of this folder to GitHub.

.DESCRIPTION
    Builds a commit containing every file in this folder (except .git internals)
    and pushes it to https://github.com/iAlirezaaa/mcp-for-blender-setup.

    The snapshot is stored with a temporary git index, so the working copy and
    the upstream tracking branch are never modified. Files ignored by
    .gitignore / .git/info/exclude are skipped, except the local helper files
    (update.ps1, update.cmd, mirror.ps1, AUTO-UPDATE.md, Repo.txt) and every
    *_cloneUpdated_* backup, which are always included.

    By default it first runs update.ps1 (safe update with backups), then
    publishes the result.

.PARAMETER NoPull
    Do not update from upstream first; just publish the current folder.

.PARAMETER Remote
    Git remote name that points at the GitHub repository (default: github).

.PARAMETER Message
    Custom commit message for the snapshot.

.PARAMETER Quiet
    Mute informational output.

.EXAMPLE
    .\mirror.ps1

.EXAMPLE
    .\mirror.ps1 -NoPull -Message "manual snapshot"

.NOTES
    Exit codes: 0 = published or nothing to publish, 1 = error.
#>
[CmdletBinding()]
param(
    [switch]$NoPull,
    [string]$Remote = 'github',
    [string]$Message,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$remoteUrl = 'https://github.com/iAlirezaaa/mcp-for-blender-setup.git'
$indexFile = Join-Path $repo '.git\mirror-index.tmp'

function Write-Info([string]$Text) {
    if (-not $Quiet) { Write-Host $Text }
}

function Invoke-Git {
    param([string[]]$GitArgs)
    # Native stderr must not turn into a terminating error (PS 5.1 behaviour).
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @GitArgs 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ Output = @($output); Code = $code }
}

function Get-HashFrom([pscustomobject]$Result) {
    $line = $Result.Output | Where-Object { $_ -is [string] -and $_ -match '^[0-9a-f]{40}$' } |
            Select-Object -Last 1
    if ($line) { return ([string]$line).Trim() }
    return $null
}

if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
    throw "Not a git repository: $repo"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git was not found in PATH."
}

# 1) Pull upstream first (default behaviour).
if (-not $NoPull) {
    Write-Info "Updating from upstream first ..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'update.ps1') -Quiet
    if ($LASTEXITCODE -ne 0) { throw "update.ps1 failed (exit $LASTEXITCODE); snapshot not published." }
}

# Jalali date for the commit message.
$persian = New-Object System.Globalization.PersianCalendar
$today = Get-Date
$stamp = '{0:0000}-{1:00}-{2:00}' -f $persian.GetYear($today),
                                      $persian.GetMonth($today),
                                      $persian.GetDayOfMonth($today)

Push-Location $repo
try {
    if (-not (git remote | Where-Object { $_ -eq $Remote })) {
        Write-Info "Adding remote '$Remote' -> $remoteUrl"
        git remote add $Remote $remoteUrl
    }
    $urlResult = Invoke-Git @('remote', 'get-url', $Remote)
    $actualUrl = ($urlResult.Output | Select-Object -First 1)
    if ($actualUrl -ne $remoteUrl) {
        throw "Remote '$Remote' points to '$actualUrl', expected '$remoteUrl'."
    }

    $upstreamResult = Invoke-Git @('rev-parse', '--short', 'HEAD')
    $upstreamHead = ([string]($upstreamResult.Output | Select-Object -First 1)).Trim()

    # Keep mirror history; fetch the current remote tip first (empty repo => ignore).
    $null = Invoke-Git @('fetch', '--quiet', $Remote, 'refs/heads/main:refs/mirror/main')
    $parentResult = Invoke-Git @('rev-parse', '--verify', '--quiet', 'refs/mirror/main')
    $parent = $null
    if ($parentResult.Code -eq 0) { $parent = Get-HashFrom $parentResult }

    # 2) Build the snapshot tree with a throw-away index.
    $forceAdd = New-Object System.Collections.Generic.List[string]
    $env:GIT_INDEX_FILE = $indexFile
    try {
        $r = Invoke-Git @('read-tree', '--empty')
        if ($r.Code -ne 0) { throw "git read-tree failed." }

        $r = Invoke-Git @('add', '-A', '--', '.')
        if ($r.Code -ne 0) { throw "git add failed: $($r.Output -join ' ')" }

        # Force-add local helper files and user backups even if ignored.
        foreach ($name in @('update.ps1', 'update.cmd', 'mirror.ps1', 'AUTO-UPDATE.md', '`Repo.txt')) {
            $full = Join-Path $repo $name
            if (Test-Path -LiteralPath $full) { $forceAdd.Add($name) }
        }
        $gitDir = (Join-Path $repo '.git') + '\'
        Get-ChildItem -LiteralPath $repo -Recurse -File -Filter '*_cloneUpdated_*' -ErrorAction SilentlyContinue |
            Where-Object { -not $_.FullName.StartsWith($gitDir, [System.StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { $forceAdd.Add($_.FullName.Substring($repo.Length + 1)) }

        if ($forceAdd.Count -gt 0) {
            $r = Invoke-Git (@('add', '-f', '--') + $forceAdd.ToArray())
            if ($r.Code -ne 0) { throw "Could not add local helper files to the snapshot." }
        }

        $r = Invoke-Git @('write-tree')
        if ($r.Code -ne 0) { throw "git write-tree failed." }
        $tree = Get-HashFrom $r
        if (-not $tree) { throw "git write-tree returned no tree hash." }
    }
    finally {
        Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $indexFile -Force -ErrorAction SilentlyContinue
    }

    $fileCount = @((Invoke-Git @('ls-tree', '-r', '--name-only', $tree)).Output).Count
    $backupCount = ($forceAdd | Where-Object { $_ -like '*_cloneUpdated_*' } | Measure-Object).Count

    if ($parent) {
        $parentTree = Get-HashFrom (Invoke-Git @('rev-parse', "$parent^{tree}"))
        if ($parentTree -eq $tree) {
            Write-Info "No changes since the last snapshot ($($parent.Substring(0, 7))); nothing to publish."
            exit 0
        }
    }

    if (-not $Message) {
        $Message = "Snapshot $stamp (upstream $upstreamHead)"
        if ($backupCount -gt 0) { $Message += " + $backupCount local backup(s)" }
    }

    $commitArgs = @('commit-tree', $tree)
    if ($parent) { $commitArgs += @('-p', $parent) }
    $commitArgs += @('-m', $Message)
    $r = Invoke-Git (@('-c', 'user.name=iAlirezaaa', '-c', 'user.email=iAlirezaaa@users.noreply.github.com') + $commitArgs)
    if ($r.Code -ne 0) { throw "git commit-tree failed: $($r.Output -join ' ')" }
    $commit = Get-HashFrom $r
    if (-not $commit) { throw "git commit-tree returned no commit hash." }

    # 3) Publish refs/mirror/main as the remote main branch.
    $r = Invoke-Git @('update-ref', 'refs/mirror/main', $commit)
    if ($r.Code -ne 0) { throw "Could not update local mirror ref." }

    $r = Invoke-Git @('push', $Remote, 'refs/mirror/main:refs/heads/main')
    if ($r.Code -ne 0) { throw "git push failed: $($r.Output -join ' ')" }

    Write-Host "Published snapshot $($commit.Substring(0, 7)) - $fileCount files, $backupCount local backup(s)."
    Write-Host "https://github.com/iAlirezaaa/mcp-for-blender-setup"
}
finally {
    Pop-Location
}
