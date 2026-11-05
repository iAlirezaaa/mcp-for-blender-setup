<#
.SYNOPSIS
    Safe update for this clone of ahujasid/mcp-for-blender.

.DESCRIPTION
    Fetches origin and fast-forwards the current branch to origin/<branch>.

    If tracked files have local changes, they are NEVER overwritten or lost:
    each changed file is renamed to
        <name>_cloneUpdated_<Jalali date><ext>
    (e.g. main_cloneUpdated_1404-08-14.py) and then the repository version is
    restored so the fast-forward can run. Untracked files that would be
    overwritten by incoming changes are moved aside the same way.

    Untracked files that do not collide with the update are left alone.

.PARAMETER Hard
    Do NOT keep backups: discard local changes to tracked files before pulling.

.PARAMETER Quiet
    Only print warnings/errors and a short result.

.EXAMPLE
    .\update.ps1

.EXAMPLE
    .\update.ps1 -Hard

.NOTES
    Exit codes: 0 = up to date or updated, 1 = error.
#>
[CmdletBinding()]
param(
    [switch]$Hard,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$backups = New-Object System.Collections.Generic.List[string]

function Write-Info([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

function Invoke-Git {
    param([string[]]$GitArgs)
    $output = & git @GitArgs 2>&1
    return [pscustomobject]@{ Output = @($output); Code = $LASTEXITCODE }
}

function Get-RelativePath([string]$FullPath) {
    $prefix = $repo.TrimEnd('\') + '\'
    if ($FullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $FullPath.Substring($prefix.Length)
    }
    return $FullPath
}

function New-BackupPath([string]$FullPath) {
    $dir  = [System.IO.Path]::GetDirectoryName($FullPath)
    $name = [System.IO.Path]::GetFileName($FullPath)
    $ext  = [System.IO.Path]::GetExtension($name)
    $stem = $name.Substring(0, $name.Length - $ext.Length)
    if ([string]::IsNullOrEmpty($stem)) { $stem = $name; $ext = '' }

    $candidate = Join-Path $dir ('{0}_cloneUpdated_{1}{2}' -f $stem, $stamp, $ext)
    $n = 2
    while (Test-Path -LiteralPath $candidate) {
        $candidate = Join-Path $dir ('{0}_cloneUpdated_{1}-{2}{3}' -f $stem, $stamp, $n, $ext)
        $n++
    }
    return $candidate
}

function Move-Aside([string]$RelativePath) {
    $full = Join-Path $repo $RelativePath
    if (-not (Test-Path -LiteralPath $full)) { return }
    $backup = New-BackupPath $full
    Move-Item -LiteralPath $full -Destination $backup -Force
    $script:backups.Add($backup)
    Write-Host ("  saved local version -> " + (Get-RelativePath $backup))
}

if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
    throw "Not a git repository: $repo"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git was not found in PATH. Install Git for Windows first."
}

# Jalali (Persian) calendar date, e.g. 1404-08-14
$persian = New-Object System.Globalization.PersianCalendar
$today = Get-Date
$stamp = '{0:0000}-{1:00}-{2:00}' -f $persian.GetYear($today),
                                      $persian.GetMonth($today),
                                      $persian.GetDayOfMonth($today)

Push-Location $repo
try {
    $branch = (& git rev-parse --abbrev-ref HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw "Could not read the current branch." }
    if ($branch -eq 'HEAD') { throw "Detached HEAD. Run: git checkout main" }

    Write-Info "Repository : $repo"
    Write-Info "Branch     : $branch"
    Write-Info "Date (Jalali): $stamp"

    $localChanges = @(& git status --porcelain --untracked-files=no) | Where-Object { $_ }

    Write-Info "Fetching origin ..."
    & git fetch --prune origin
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed (network problem?)." }

    $old = (& git rev-parse HEAD).Trim()
    $upstream = "origin/$branch"
    $new = (& git rev-parse --verify --quiet $upstream)
    if ($LASTEXITCODE -ne 0 -or -not $new) { throw "Remote branch '$upstream' not found." }
    $new = $new.Trim()

    if ($old -eq $new) {
        if ($localChanges.Count -gt 0) {
            Write-Info ("Already up to date ({0}). Your {1} local change(s) were left untouched." -f `
                        $old.Substring(0, 7), $localChanges.Count)
        }
        else {
            Write-Info "Already up to date ($($old.Substring(0, 7)))."
        }
        exit 0
    }

    & git merge-base --is-ancestor $new $old
    if ($LASTEXITCODE -eq 0) {
        $ahead = (& git rev-list --count "$new..$old").Trim()
        Write-Info "Local branch is ahead of $upstream by $ahead commit(s); nothing to pull."
        exit 0
    }

    if ($Hard) {
        if ($localChanges.Count -gt 0) {
            Write-Info "Discarding local changes to tracked files (-Hard, no backups)."
            & git reset --hard HEAD | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "git reset --hard failed." }
        }
    }
    else {
        # 1) Tracked files modified or deleted locally -> keep a dated copy, restore from HEAD.
        $modified = @(& git -c core.quotePath=false diff --name-only --diff-filter=ACMRT HEAD) |
                    Where-Object { $_ }
        $deleted  = @(& git -c core.quotePath=false diff --name-only --diff-filter=D HEAD) |
                    Where-Object { $_ }

        if ($modified.Count -gt 0) {
            Write-Info "Keeping your local version of $($modified.Count) changed file(s):"
            foreach ($path in $modified) { Move-Aside $path }
        }

        $restore = @($modified) + @($deleted)
        if ($restore.Count -gt 0) {
            & git checkout HEAD -- @restore
            if ($LASTEXITCODE -ne 0) { throw "Could not restore tracked files before updating." }
        }

        # 2) Untracked files that the incoming update would overwrite -> move them aside too.
        $tracked = @{}
        foreach ($item in @(& git ls-files)) {
            if ($item) { $tracked[$item.ToLowerInvariant()] = $true }
        }
        $incoming = @(& git -c core.quotePath=false diff --name-only --diff-filter=ACMRT "$old" "$new") |
                    Where-Object { $_ }
        foreach ($path in $incoming) {
            $full = Join-Path $repo $path
            if (-not (Test-Path -LiteralPath $full)) { continue }
            if (-not $tracked.ContainsKey($path.ToLowerInvariant())) {
                Write-Info "Untracked file conflicts with the update:"
                Move-Aside $path
            }
        }

        if ($modified.Count -eq 0 -and $deleted.Count -eq 0 -and $backups.Count -eq 0) {
            Write-Info "No local changes to preserve."
        }
    }

    & git merge --ff-only $upstream
    if ($LASTEXITCODE -ne 0) { throw "Fast-forward failed (histories diverged). Resolve manually." }

    $count = (& git rev-list --count "$old..HEAD").Trim()
    Write-Host "Updated: $count new commit(s) - now at $((& git rev-parse --short HEAD).Trim())."

    if (-not $Quiet) {
        Write-Host ""
        & git --no-pager log --oneline --no-decorate "$old..HEAD"
        Write-Host ""
        & git --no-pager diff --stat "$old..HEAD"
    }

    if ($backups.Count -gt 0) {
        Write-Host ""
        Write-Host ("Local versions kept ({0}):" -f $stamp)
        foreach ($file in $backups) { Write-Host ("  " + (Get-RelativePath $file)) }
    }
}
finally {
    Pop-Location
}
