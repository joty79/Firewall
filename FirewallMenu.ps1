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

function Get-CachedRuleData {
    $All = @(Get-NetFirewallRule -DisplayName "${RulePrefix}*" -ErrorAction SilentlyContinue)
    if ($All.Count -eq 0) { return @() }

    # Batch: pipe all rules to get filters in ONE CIM pass
    $batchFilters = @($All | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue)

    # Build lookup by EVERY key we can think of (InstanceID + Name)
    $progMap = @{}
    foreach ($f in $batchFilters) {
        if ($f.Program) {
            $progMap[$f.InstanceID] = $f.Program
            $progMap[$f.Name]       = $f.Program
        }
    }

    $result = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($r in $All) {
        $path = $progMap[$r.InstanceID]
        if (-not $path) { $path = $progMap[$r.Name] }
        # Last-resort fallback: individual CIM call (only for unmatched rules)
        if (-not $path) {
            try {
                $f = $r | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
                if ($f) { $path = $f.Program }
            } catch {}
        }
        $dir = if ($path) { Split-Path -Path $path -Parent -ErrorAction SilentlyContinue } else { "Unknown Path" }
        $result.Add([pscustomobject]@{
            DisplayName = $r.DisplayName
            Direction   = [string]$r.Direction
            Folder      = $dir
            Path        = $path
            RuleName    = $r.Name
        })
    }
    return ,$result
}

function Show-InteractiveRules {
    while ($true) {
        $cached = Get-CachedRuleData
        if ($cached.Count -eq 0) {
            Write-Host "`n$($_C.Warn)No rules created by this script yet.$($_C.Reset)"
            Pause-Menu
            return
        }

        $Grouped = $cached | Group-Object Folder | Sort-Object Name

        # BMP-safe folder icon
        $fIcon = [char]0x25B6  # Black right-pointing triangle

        $folderOptions = @()
        foreach ($group in $Grouped) {
            $exeCount = ($group.Group | Select-Object -ExpandProperty Path -Unique).Count
            $folderOptions += "$fIcon $($group.Name) ($exeCount exe, $($group.Group.Count) rules)"
        }
        $folderOptions += "$([char]0x2190) Back"

        $header = { Write-UiBanner -Title "FIREWALL RULES" -Subtitle "Select a folder to view or manage" }
        $folderChoice = Invoke-ArrowMenu -Items $folderOptions -Title "Blocked Folders" -HeaderBlock $header

        if ($null -eq $folderChoice -or $folderChoice -match 'Back$') { return }

        # Match by stripping icon prefix
        $selectedGroup = $Grouped | Where-Object {
            $exeCount = ($_.Group | Select-Object -ExpandProperty Path -Unique).Count
            "$fIcon $($_.Name) ($exeCount exe, $($_.Group.Count) rules)" -eq $folderChoice
        }
        if ($selectedGroup) {
            Show-FolderRulesInteractive -FolderPath $selectedGroup.Name -CachedRules $cached
        }
    }
}

function Show-FolderRulesInteractive {
    param(
        [string]$FolderPath,
        [System.Collections.Generic.List[pscustomobject]]$CachedRules
    )

    $folderRules = @($CachedRules | Where-Object Folder -eq $FolderPath)
    if ($folderRules.Count -eq 0) { return }

    # Track DESIRED state per exe path: $true = blocked, $false = unblocked
    # Changes are only applied to Windows Firewall when leaving this menu
    $toggleState = [ordered]@{}
    $exePaths = @($folderRules | Select-Object -ExpandProperty Path -Unique | Sort-Object)
    foreach ($p in $exePaths) { $toggleState[$p] = $true }

    # BMP-safe icons
    $iconBlocked  = [char]0x25CF  # filled circle = blocked
    $iconOpen     = [char]0x25CB  # hollow circle = open

    $lastChoice = ''

    while ($true) {
        $fileOptions = @()
        $fileOptions += "$([char]0x26A1) TOGGLE ALL"

        $labelToPath = @{}
        foreach ($p in $toggleState.Keys) {
            $fname = Split-Path -Path $p -Leaf
            $rules = @($folderRules | Where-Object Path -eq $p)
            $inRule = ($rules | Where-Object Direction -eq 'Inbound').Count -gt 0
            $outRule = ($rules | Where-Object Direction -eq 'Outbound').Count -gt 0
            $dirInfo = ""
            if ($inRule -and $outRule) { $dirInfo = "[IN+OUT]" }
            elseif ($inRule) { $dirInfo = "[IN ONLY]" }
            elseif ($outRule) { $dirInfo = "[OUT ONLY]" }

            if ($toggleState[$p]) {
                $label = "$iconBlocked BLOCKED  $fname $dirInfo"
            } else {
                $label = "$iconOpen OPEN     $fname $dirInfo"
            }
            $fileOptions += $label
            $labelToPath[$label] = $p
        }
        $fileOptions += "$([char]0x2190) Apply & Back"

        $pendingCount = @($toggleState.Values | Where-Object { -not $_ }).Count
        $subtitle = if ($pendingCount -gt 0) { "$FolderPath  ($pendingCount pending unblock)" } else { $FolderPath }

        $header = { Write-UiBanner -Title "FOLDER RULES" -Subtitle $subtitle }
        $fileChoice = Invoke-ArrowMenu -Items $fileOptions -Title "Enter = toggle on/off, Esc = apply changes & back" -HeaderBlock $header -CurrentItem $lastChoice

        if ($null -eq $fileChoice -or $fileChoice -match 'Apply.*Back$') {
            # Apply all pending changes NOW
            foreach ($p in $toggleState.Keys) {
                if (-not $toggleState[$p]) {
                    # Was blocked, now should be unblocked -> remove rules
                    $rName = "${RulePrefix}$(Split-Path $p -Leaf)"
                    Remove-NetFirewallRule -DisplayName "$rName*" -ErrorAction SilentlyContinue
                }
            }
            return
        }

        if ($fileChoice -match 'TOGGLE ALL') {
            # If any are blocked, unblock all. If all are open, re-block all.
            $anyBlocked = @($toggleState.Values | Where-Object { $_ }).Count -gt 0
            foreach ($p in @($toggleState.Keys)) {
                $toggleState[$p] = -not $anyBlocked
            }
            $lastChoice = $fileChoice
            continue
        }

        $selectedPath = $labelToPath[$fileChoice]
        if ($selectedPath) {
            # Just flip the visual state, no firewall changes yet
            $toggleState[$selectedPath] = -not $toggleState[$selectedPath]

            # Build what the NEW label will be so -CurrentItem can find it
            $fname = Split-Path -Path $selectedPath -Leaf
            $rules = @($folderRules | Where-Object Path -eq $selectedPath)
            $inRule = ($rules | Where-Object Direction -eq 'Inbound').Count -gt 0
            $outRule = ($rules | Where-Object Direction -eq 'Outbound').Count -gt 0
            $dirInfo = ""
            if ($inRule -and $outRule) { $dirInfo = "[IN+OUT]" }
            elseif ($inRule) { $dirInfo = "[IN ONLY]" }
            elseif ($outRule) { $dirInfo = "[OUT ONLY]" }
            if ($toggleState[$selectedPath]) {
                $lastChoice = "$iconBlocked BLOCKED  $fname $dirInfo"
            } else {
                $lastChoice = "$iconOpen OPEN     $fname $dirInfo"
            }
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
