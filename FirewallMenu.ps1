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
# 🔵 Load TUI Blueprint
# -----------------------------------------------------------
$BlueprintPath = "C:\Users\joty79\.agent-shared\templates\PS_UI_Blueprint.psm1"
if (Test-Path -LiteralPath $BlueprintPath) {
    Invoke-Expression (Get-Content -LiteralPath $BlueprintPath -Raw)
} else {
    Write-Warning "UI Blueprint not found at $BlueprintPath. UI features may fail."
}

# -----------------------------------------------------------
# 🔵 Initialization
# -----------------------------------------------------------
# 🔸 FIX: Use -LiteralPath to handle [brackets] correctly
if (Test-Path -LiteralPath $TargetItem) {
    $Item = Get-Item -LiteralPath $TargetItem
    $FullPath = $Item.FullName
    $FileName = $Item.Name
    $IsFolder = $Item.PSIsContainer
} else {
    Write-Error "File or Folder not found."; Start-Sleep 3; exit
}

if ($IsFolder) {
    $ExeFiles = Get-ChildItem -LiteralPath $FullPath -Filter "*.exe" -Recurse -File -ErrorAction SilentlyContinue
} else {
    $ExeFiles = @($Item)
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

# Get-FastStatus removed (inlined into Main Loop for performance)

function Do-DeepScan {
    Write-Host "`n🔍 Deep Scanning all Windows Rules for target (This takes time)..." -ForegroundColor Cyan
    $TargetPaths = $ExeFiles.FullName
    $AllRules = Get-NetFirewallRule -ErrorAction SilentlyContinue | Where-Object {
        $prog = ($_ | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue).Program
        $prog -in $TargetPaths
    }
    
    if ($AllRules) {
        $AllRules | Select-Object DisplayName, Direction, Action, Enabled | Format-Table -AutoSize
    } else {
        Write-Host "✅ No hidden rules found from other apps." -ForegroundColor Green
    }
    Pause-Menu
}

function Toggle-Block {
    if ($ExeFiles.Count -eq 0) {
        Write-Host "`n⚠️ No executables found in this folder." -ForegroundColor Yellow
        Pause-Menu
        return
    }

    $HasRules = $false
    foreach ($exe in $ExeFiles) {
        $rName = "${RulePrefix}$($exe.Name)"
        if (Get-NetFirewallRule -DisplayName "$rName*" -ErrorAction SilentlyContinue) {
            $HasRules = $true
            break
        }
    }
    
    if ($HasRules) {
        Write-Host "`n✅ Rules Deleted. Access Restored for $($ExeFiles.Count) files." -ForegroundColor Green
        foreach ($exe in $ExeFiles) {
            $rName = "${RulePrefix}$($exe.Name)"
            Remove-NetFirewallRule -DisplayName "$rName*" -ErrorAction SilentlyContinue
        }
    } else {
        Write-Host "`n⛔ Creating Block Rules for $($ExeFiles.Count) files..." -ForegroundColor Magenta
        foreach ($exe in $ExeFiles) {
            $rName = "${RulePrefix}$($exe.Name)"
            New-NetFirewallRule -DisplayName "$rName (In)" -Program $exe.FullName -Direction Inbound -Action Block -Profile Any | Out-Null
            New-NetFirewallRule -DisplayName "$rName (Out)" -Program $exe.FullName -Direction Outbound -Action Block -Profile Any | Out-Null
        }
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

function Show-InteractiveRules {
    while ($true) {
        $All = Get-NetFirewallRule -DisplayName "${RulePrefix}*" -ErrorAction SilentlyContinue
        if (-not $All) {
            Write-Host "`n⚠️ No rules created by this script yet." -ForegroundColor Yellow
            Pause-Menu
            return
        }
        
        $RuleData = @()
        foreach ($r in $All) {
            $filter = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            $path = $filter.Program
            if ($path) {
                $dir = Split-Path -Path $path -Parent -ErrorAction SilentlyContinue
            } else {
                $dir = "Unknown Path"
            }
            $RuleData += [pscustomobject]@{
                DisplayName = $r.DisplayName
                Folder = $dir
            }
        }
        
        $Grouped = $RuleData | Group-Object Folder | Sort-Object Name
        
        $folderOptions = @()
        foreach ($group in $Grouped) {
            $folderOptions += "📁 $($group.Name) ($($group.Group.Count) rules)"
        }
        $folderOptions += "🔙 Back"
        
        $header = { Write-UiBanner -Title "FIREWALL RULES" -Subtitle "Select a folder to view or manage affected files" }
        $folderChoice = Invoke-ArrowMenu -Items $folderOptions -Title "Blocked Folders" -HeaderBlock $header
        
        if ($null -eq $folderChoice -or $folderChoice -eq "🔙 Back") { return }
        
        $selectedFolderGroup = $Grouped | Where-Object { "📁 $($_.Name) ($($_.Group.Count) rules)" -eq $folderChoice }
        if ($selectedFolderGroup) {
            Show-FolderRulesInteractive -FolderPath $selectedFolderGroup.Name
        }
    }
}

function Show-FolderRulesInteractive {
    param([string]$FolderPath)
    
    while ($true) {
        $All = Get-NetFirewallRule -DisplayName "${RulePrefix}*" -ErrorAction SilentlyContinue
        if (-not $All) { return }
        
        $folderRules = @()
        foreach ($r in $All) {
            $filter = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
            $path = $filter.Program
            if ($path) {
                $dir = Split-Path -Path $path -Parent -ErrorAction SilentlyContinue
                if ($dir -eq $FolderPath) {
                    $folderRules += [pscustomobject]@{
                        RuleObj = $r
                        Path = $path
                        Direction = $r.Direction
                        Name = $r.Name
                    }
                }
            }
        }
        
        if ($folderRules.Count -eq 0) { return } # All rules deleted, go back
        
        $files = $folderRules | Group-Object Path | Sort-Object Name
        $fileOptions = @()
        $fileOptions += "⚡ UNBLOCK ALL (Remove all rules in this folder)"
        
        $fileMap = @{}
        foreach ($f in $files) {
            $fname = Split-Path -Path $f.Name -Leaf -ErrorAction SilentlyContinue
            $inRule = ($f.Group | Where-Object Direction -eq 'Inbound') -ne $null
            $outRule = ($f.Group | Where-Object Direction -eq 'Outbound') -ne $null
            $status = ""
            if ($inRule -and $outRule) { $status = "[IN+OUT]" }
            elseif ($inRule) { $status = "[IN ONLY]" }
            elseif ($outRule) { $status = "[OUT ONLY]" }
            
            $label = "📄 $fname $status"
            $fileOptions += $label
            $fileMap[$label] = $f.Group
        }
        $fileOptions += "🔙 Back"
        
        $header = { Write-UiBanner -Title "FOLDER RULES" -Subtitle $FolderPath }
        $fileChoice = Invoke-ArrowMenu -Items $fileOptions -Title "Select an executable to UNBLOCK it" -HeaderBlock $header
        
        if ($null -eq $fileChoice -or $fileChoice -eq "🔙 Back") { return }
        
        if ($fileChoice -eq "⚡ UNBLOCK ALL (Remove all rules in this folder)") {
            foreach ($r in $folderRules) {
                Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
            }
            Write-Host "`n✅ All rules for this folder have been removed." -ForegroundColor Green
            Start-Sleep -Seconds 1
            return
        }
        
        $rulesToDelete = $fileMap[$fileChoice]
        if ($rulesToDelete) {
            foreach ($r in $rulesToDelete) {
                Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
            }
            Write-Host "`n✅ Rule(s) removed for $($rulesToDelete[0].Path)" -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
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
$options = @(
    "⚡ Toggle Block/Allow (Instant)",
    "🐢 Deep Scan (Check external rules)",
    "📋 List/Manage ALL rules (Interactive)",
    "🔎 Search inside our rules",
    "🔄 Update app",
    "🚪 Quit"
)

while ($true) {
    # 🔸 FIX: Pre-compute heavy status ONCE per loop iteration to avoid UI lag on keystrokes
    $BlockedCount = 0
    foreach ($exe in $ExeFiles) {
        $rName = "${RulePrefix}$($exe.Name)"
        if (Get-NetFirewallRule -DisplayName "$rName*" -ErrorAction SilentlyContinue) {
            $BlockedCount++
        }
    }
    $targetDesc = if ($IsFolder) { "Folder: $FileName ($($ExeFiles.Count) EXEs)" } else { "File: $FileName" }
    
    $cachedFirewallStatus = Get-ActiveFirewallProfileStatus
    
    $header = {
        Write-UiBanner -Title "FIREWALL MANAGER" -Subtitle "v$($UpdateStatus.Version) · $($UpdateStatus.Message)"
        
        if ($BlockedCount -gt 0) {
            Write-Host "  $($_C.Fail)$($_C.Bold)[ BLOCKED BY US ($BlockedCount/$($ExeFiles.Count)) ]$($_C.Reset) $($_C.Dim)Target: $targetDesc$($_C.Reset)"
        } else {
            Write-Host "  $($_C.OK)$($_C.Bold)[ ALLOWED (BY US) ]$($_C.Reset) $($_C.Dim)Target: $targetDesc$($_C.Reset)"
        }
        
        if ($cachedFirewallStatus.IsDisabled) {
            Write-Host "  $($_C.Warn)$($cachedFirewallStatus.Text)$($_C.Reset)"
            Write-Host "  $($_C.Dim)$($cachedFirewallStatus.Detail)$($_C.Reset)"
        } else {
            Write-Host "  $($_C.OK)$($cachedFirewallStatus.Text)$($_C.Reset)"
        }
    }

    $choice = Invoke-ArrowMenu -Items $options -Title "Main Menu" -HeaderBlock $header

    switch ($choice) {
        "⚡ Toggle Block/Allow (Instant)" { Toggle-Block }
        "🐢 Deep Scan (Check external rules)" { Do-DeepScan }
        "📋 List/Manage ALL rules (Interactive)" { Show-InteractiveRules }
        "🔎 Search inside our rules" { Search-My-Rules }
        "🔄 Update app" { Invoke-UpdateApp; $UpdateStatus = Get-UpdateStatus }
        "🚪 Quit" { exit }
        $null { exit }
    }
}
