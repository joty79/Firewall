# Requires -Version 7.0
param ([AllowEmptyString()][string]$TargetItem)

# -----------------------------------------------------------
# 🔵 Setup & Admin Check
# -----------------------------------------------------------
$HOST.UI.RawUI.WindowTitle = "Firewall Manager"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    $WTArgs = "-- pwsh.exe -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TargetItem `"$TargetItem`""
    Start-Process wt.exe -ArgumentList $WTArgs -Verb RunAs
    exit
}

# -----------------------------------------------------------
# 🔵 Initialization
# -----------------------------------------------------------
# 🔸 FIX: Use -LiteralPath to handle [brackets] correctly
if (Test-Path -LiteralPath $TargetItem) {
    $Item = Get-Item -LiteralPath $TargetItem
    $FullPath = $Item.FullName
    $FileName = $Item.Name
} else {
    Write-Error "File not found."; Start-Sleep 3; exit
}

$RulePrefix = "_FW_BLOCK_"
$RuleName = "$RulePrefix$FileName"
$AppRoot = $PSScriptRoot
$InstallScript = Join-Path $AppRoot 'Install.ps1'
$MetadataPath = Join-Path $AppRoot 'app-metadata.json'
$InstallMetaPath = Join-Path $AppRoot 'state\install-meta.json'
$InstallerLogPath = Join-Path $AppRoot 'logs\installer.log'
$GitHubRepo = 'joty79/Firewall'
$GitHubBranch = 'master'
$UpdateStatus = $null

# -----------------------------------------------------------
# 🔵 Functions
# -----------------------------------------------------------

function Invoke-CommandText {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][string[]]$CommandArgs,
        [int]$TimeoutSeconds = 10
    )

    try {
        $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $processInfo.FileName = $FileName
        foreach ($commandArg in $CommandArgs) {
            [void]$processInfo.ArgumentList.Add($commandArg)
        }
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = [System.Diagnostics.Process]::Start($processInfo)
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill() } catch { }
            return $null
        }

        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0) {
            if ($stderr) { return $null }
            return $null
        }
        return $stdout
    } catch {
        return $null
    }
}

function Get-AppVersion {
    if (-not (Test-Path -LiteralPath $MetadataPath)) { return 'dev' }
    try {
        $metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($metadata.version) { return [string]$metadata.version }
    } catch { }
    return 'dev'
}

function Get-LocalCommit {
    if (Test-Path -LiteralPath (Join-Path $AppRoot '.git')) {
        return Invoke-CommandText -FileName 'git.exe' -CommandArgs @('-C', $AppRoot, 'rev-parse', 'HEAD') -TimeoutSeconds 5
    }

    if (Test-Path -LiteralPath $InstallMetaPath) {
        try {
            $installMeta = Get-Content -LiteralPath $InstallMetaPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($installMeta.github_commit) { return [string]$installMeta.github_commit }
        } catch { }
    }

    return $null
}

function Test-GitDirty {
    if (-not (Test-Path -LiteralPath (Join-Path $AppRoot '.git'))) { return $false }
    $status = Invoke-CommandText -FileName 'git.exe' -CommandArgs @('-C', $AppRoot, 'status', '--porcelain') -TimeoutSeconds 5
    return -not [string]::IsNullOrWhiteSpace($status)
}

function Get-RemoteCommit {
    $remote = Invoke-CommandText -FileName 'git.exe' -CommandArgs @('ls-remote', "https://github.com/$GitHubRepo.git", "refs/heads/$GitHubBranch") -TimeoutSeconds 5
    if (-not [string]::IsNullOrWhiteSpace($remote)) {
        return ($remote -split "\s+")[0]
    }

    $fallbackRemote = Invoke-CommandText -FileName 'git.exe' -CommandArgs @('ls-remote', "git@github.com:$GitHubRepo.git", "refs/heads/$GitHubBranch") -TimeoutSeconds 5
    if (-not [string]::IsNullOrWhiteSpace($fallbackRemote)) {
        return ($fallbackRemote -split "\s+")[0]
    }

    return $null
}

function Get-UpdateStatus {
    $version = Get-AppVersion
    $localCommit = Get-LocalCommit
    $remoteCommit = Get-RemoteCommit
    $isDirty = Test-GitDirty

    if ($isDirty) {
        return [pscustomobject]@{
            State        = 'Dirty'
            Version      = $version
            LocalCommit  = $localCommit
            RemoteCommit = $remoteCommit
            Message      = "Update: local changes"
        }
    }

    if ([string]::IsNullOrWhiteSpace($remoteCommit)) {
        return [pscustomobject]@{
            State        = 'Unknown'
            Version      = $version
            LocalCommit  = $localCommit
            RemoteCommit = $null
            Message      = "Update: unknown"
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($localCommit) -and $localCommit -ne $remoteCommit) {
        return [pscustomobject]@{
            State        = 'Available'
            Version      = $version
            LocalCommit  = $localCommit
            RemoteCommit = $remoteCommit
            Message      = "Update: available"
        }
    }

    return [pscustomobject]@{
        State        = 'Current'
        Version      = $version
        LocalCommit  = $localCommit
        RemoteCommit = $remoteCommit
        Message      = "Update: current"
    }
}

function Format-Commit {
    param([AllowEmptyString()][string]$Commit)
    if ([string]::IsNullOrWhiteSpace($Commit)) { return 'n/a' }
    if ($Commit.Length -lt 12) { return $Commit }
    return $Commit.Substring(0, 12)
}

function Get-ActiveFirewallProfileStatus {
    $activeCategories = @()

    try {
        $connections = @(Get-NetConnectionProfile -ErrorAction Stop)
        foreach ($connection in $connections) {
            $hasConnectivity = ($connection.IPv4Connectivity -ne 'Disconnected') -or ($connection.IPv6Connectivity -ne 'Disconnected')
            if (-not $hasConnectivity) { continue }

            $profileName = switch ([string]$connection.NetworkCategory) {
                'DomainAuthenticated' { 'Domain' }
                'Private' { 'Private' }
                'Public' { 'Public' }
                default { 'Public' }
            }

            if ($activeCategories -notcontains $profileName) {
                $activeCategories += $profileName
            }
        }
    } catch { }

    if ($activeCategories.Count -eq 0) {
        $activeCategories = @('Domain', 'Private', 'Public')
    }

    $disabledProfiles = @()
    $enabledProfiles = @()
    foreach ($profileName in $activeCategories) {
        try {
            $firewallProfile = Get-NetFirewallProfile -Name $profileName -ErrorAction Stop
            if ($firewallProfile.Enabled) {
                $enabledProfiles += $profileName
            } else {
                $disabledProfiles += $profileName
            }
        } catch { }
    }

    if ($disabledProfiles.Count -gt 0) {
        return [pscustomobject]@{
            IsDisabled = $true
            Text       = "Firewall DISABLED for active profile(s): $($disabledProfiles -join ', ')"
            Detail     = "Rules can exist but will not be enforced until Windows Firewall is enabled."
        }
    }

    if ($enabledProfiles.Count -gt 0) {
        return [pscustomobject]@{
            IsDisabled = $false
            Text       = "Firewall enabled for active profile(s): $($enabledProfiles -join ', ')"
            Detail     = ''
        }
    }

    return [pscustomobject]@{
        IsDisabled = $false
        Text       = 'Firewall status unavailable'
        Detail     = 'Could not read the current network firewall profile.'
    }
}

function Get-FastStatus {
    # Ακαριαίος έλεγχος μόνο με το όνομα (Index Search)
    $MyRules = Get-NetFirewallRule -DisplayName "$RuleName*" -ErrorAction SilentlyContinue
    if ($MyRules) {
        Write-Host " [ BLOCKED BY US ] " -NoNewline -ForegroundColor White -BackgroundColor Red
    } else {
        Write-Host " [ ALLOWED (BY US) ] " -NoNewline -ForegroundColor Black -BackgroundColor Green
    }
    Write-Host " Target: $FileName" -ForegroundColor Gray
}

function Do-DeepScan {
    Write-Host "`n🔍 Deep Scanning all Windows Rules (This takes time)..." -ForegroundColor Cyan
    $AllRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        ($_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program -eq $FullPath
    }
    
    if ($AllRules) {
        $AllRules | Select-Object DisplayName, Direction, Action, Enabled | Format-Table -AutoSize
    } else {
        Write-Host "✅ No hidden rules found from other apps." -ForegroundColor Green
    }
    Pause-Menu
}

function Toggle-Block {
    $Exists = Get-NetFirewallRule -DisplayName "$RuleName*" -ErrorAction SilentlyContinue
    
    if ($Exists) {
        Remove-NetFirewallRule -DisplayName "$RuleName*"
        Write-Host "`n✅ Rules Deleted. Access Restored." -ForegroundColor Green
    } else {
        Write-Host "`n⛔ Creating Block Rules..." -ForegroundColor Magenta
        New-NetFirewallRule -DisplayName "$RuleName (In)" -Program $FullPath -Direction Inbound -Action Block -Profile Any | Out-Null
        New-NetFirewallRule -DisplayName "$RuleName (Out)" -Program $FullPath -Direction Outbound -Action Block -Profile Any | Out-Null
        Write-Host "✅ Blocked Successfully." -ForegroundColor Green
        $firewallStatus = Get-ActiveFirewallProfileStatus
        if ($firewallStatus.IsDisabled) {
            Write-Host "`n⚠️ $($firewallStatus.Text)" -ForegroundColor Yellow
            Write-Host "   $($firewallStatus.Detail)" -ForegroundColor Yellow
            Pause-Menu
        }
    }
    Start-Sleep -Seconds 1
}

function Show-All-My-Rules {
    Clear-Host
    Write-Host "🔵 All Rules Created by This Script:`n" -ForegroundColor Cyan
    $All = Get-NetFirewallRule -DisplayName "${RulePrefix}*" -ErrorAction SilentlyContinue
    if ($All) {
        $All | Select-Object DisplayName, Direction, Action | Format-Table -AutoSize
    } else {
        Write-Host "⚠️ No rules created by this script yet." -ForegroundColor Yellow
    }
    Pause-Menu
}

function Search-My-Rules {
    $Search = Read-Host "`n🔎 Type app name to search (our rules only)"
    
    if (-not [string]::IsNullOrWhiteSpace($Search)) {
        # Αποθηκεύουμε τα αποτελέσματα για να τα ελέγξουμε
        $Results = Get-NetFirewallRule -DisplayName "${RulePrefix}*$Search*" -ErrorAction SilentlyContinue
        
        if ($Results) {
            Write-Host "`n✅ Found $(@($Results).Count) rule(s):" -ForegroundColor Green
            $Results | Select-Object DisplayName, Action | Format-Table -AutoSize
        } else {
            # Εδώ είναι η διόρθωση που ζήτησες
            Write-Host "`n⚠️ No rules found matching '$Search'." -ForegroundColor Yellow
        }
    }
    Pause-Menu
}

function Pause-Menu {
    Write-Host "`nPress any key to return..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-RecentInstallerLog {
    if (-not (Test-Path -LiteralPath $InstallerLogPath)) {
        Write-Host "`nNo installer log found yet." -ForegroundColor DarkGray
        return
    }

    Write-Host "`nRecent installer output:" -ForegroundColor Cyan
    Get-Content -LiteralPath $InstallerLogPath -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  $PSItem" -ForegroundColor DarkGray
    }
}

function Restart-AppHost {
    $targetArg = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -TargetItem `"$FullPath`""
    try {
        Start-Process wt.exe -ArgumentList "--title `"Firewall Manager`" pwsh.exe $targetArg" -Verb RunAs
    } catch {
        Start-Process pwsh.exe -ArgumentList $targetArg -Verb RunAs
    }
}

function Invoke-UpdateApp {
    Clear-Host
    Write-Host "🔵 Update Firewall" -ForegroundColor Cyan
    Write-Host "--------------------------------" -ForegroundColor Gray
    $script:UpdateStatus = Get-UpdateStatus
    Write-Host "Status: $($script:UpdateStatus.Message)" -ForegroundColor White
    Write-Host "Version: $($script:UpdateStatus.Version)" -ForegroundColor Gray
    Write-Host "Current commit: $(Format-Commit $script:UpdateStatus.LocalCommit)" -ForegroundColor Gray
    Write-Host "Latest commit:  $(Format-Commit $script:UpdateStatus.RemoteCommit)" -ForegroundColor Gray

    if ($script:UpdateStatus.State -eq 'Dirty') {
        Write-Host "`n⚠️ Local git changes detected. Refusing automatic update." -ForegroundColor Yellow
        Pause-Menu
        return
    }

    if ($script:UpdateStatus.State -eq 'Current') {
        Write-Host "`n✅ Already up to date." -ForegroundColor Green
        Show-RecentInstallerLog
        Pause-Menu
        return
    }

    if ($script:UpdateStatus.State -eq 'Unknown') {
        Write-Host "`n⚠️ Fresh remote check failed. Not using stale UpToDate fallback." -ForegroundColor Yellow
        Show-RecentInstallerLog
        Pause-Menu
        return
    }

    Write-Host "`nRun update now? [Y/n] " -NoNewline -ForegroundColor Yellow
    $answer = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString()
    Write-Host $answer
    if ($answer -and $answer.ToUpperInvariant() -ne 'Y') { return }

    if (Test-Path -LiteralPath (Join-Path $AppRoot '.git')) {
        Write-Host "`nFetching latest git metadata..." -ForegroundColor Cyan
        & git.exe -C $AppRoot fetch origin $GitHubBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ git fetch failed with exit code $LASTEXITCODE." -ForegroundColor Red
            Pause-Menu
            return
        }

        Write-Host "Fast-forwarding working copy..." -ForegroundColor Cyan
        & git.exe -C $AppRoot pull --ff-only origin $GitHubBranch
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ git pull --ff-only failed with exit code $LASTEXITCODE." -ForegroundColor Red
            Pause-Menu
            return
        }
    } elseif (Test-Path -LiteralPath $InstallScript) {
        Write-Host "`nRunning generated InstallerCore updater..." -ForegroundColor Cyan
        & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript -Action UpdateGitHub -Force -NoExplorerRestart
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`n❌ Installer update failed with exit code $LASTEXITCODE." -ForegroundColor Red
            Show-RecentInstallerLog
            Pause-Menu
            return
        }
    } else {
        Write-Host "`n❌ Install.ps1 was not found, so the update backend is unavailable." -ForegroundColor Red
        Pause-Menu
        return
    }

    Show-RecentInstallerLog
    Write-Host "`n✅ Update completed. Relaunching Firewall Manager..." -ForegroundColor Green
    Start-Sleep -Seconds 1
    Restart-AppHost
    exit
}

$UpdateStatus = Get-UpdateStatus

# -----------------------------------------------------------
# 🔵 Main Loop
# -----------------------------------------------------------
do {
    Clear-Host
    Write-Host "🔵 FIREWALL MANAGER" -ForegroundColor Cyan
    Write-Host "--------------------------------" -ForegroundColor Gray
    Get-FastStatus
    $firewallStatus = Get-ActiveFirewallProfileStatus
    if ($firewallStatus.IsDisabled) {
        Write-Host "⚠️ $($firewallStatus.Text)" -ForegroundColor Yellow
        Write-Host "   $($firewallStatus.Detail)" -ForegroundColor Yellow
    } else {
        Write-Host "✅ $($firewallStatus.Text)" -ForegroundColor Green
    }
    Write-Host "$($UpdateStatus.Message) · v$($UpdateStatus.Version)" -ForegroundColor DarkGray
    Write-Host "--------------------------------`n" -ForegroundColor Gray

    Write-Host "1. ⚡ Toggle Block/Allow (Instant)" -ForegroundColor White
    Write-Host "2. 🐢 Deep Scan (Check external rules)" -ForegroundColor Yellow
    Write-Host "3. 📋 List ALL rules created by script" -ForegroundColor Gray
    Write-Host "4. 🔎 Search inside our rules" -ForegroundColor Gray
    Write-Host "5. 🔄 Update app" -ForegroundColor Gray
    Write-Host "Q.    Quit" -ForegroundColor DarkGray

    $Choice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToUpper()

    switch ($Choice) {
        '1' { Toggle-Block }
        '2' { Do-DeepScan }
        '3' { Show-All-My-Rules }
        '4' { Search-My-Rules }
        '5' { Invoke-UpdateApp; $UpdateStatus = Get-UpdateStatus }
        'Q' { exit }
    }
} until ($Choice -eq 'Q')
