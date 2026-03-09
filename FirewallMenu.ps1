# Requires -Version 7.0
param ([string]$TargetItem)

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

# -----------------------------------------------------------
# 🔵 Functions
# -----------------------------------------------------------

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

# -----------------------------------------------------------
# 🔵 Main Loop
# -----------------------------------------------------------
do {
    Clear-Host
    Write-Host "🔵 FIREWALL MANAGER" -ForegroundColor Cyan
    Write-Host "--------------------------------" -ForegroundColor Gray
    Get-FastStatus
    Write-Host "--------------------------------`n" -ForegroundColor Gray

    Write-Host "1. ⚡ Toggle Block/Allow (Instant)" -ForegroundColor White
    Write-Host "2. 🐢 Deep Scan (Check external rules)" -ForegroundColor Yellow
    Write-Host "3. 📋 List ALL rules created by script" -ForegroundColor Gray
    Write-Host "4. 🔎 Search inside our rules" -ForegroundColor Gray
    Write-Host "Q.    Quit" -ForegroundColor DarkGray

    $Choice = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown").Character.ToString().ToUpper()

    switch ($Choice) {
        '1' { Toggle-Block }
        '2' { Do-DeepScan }
        '3' { Show-All-My-Rules }
        '4' { Search-My-Rules }
        'Q' { exit }
    }
} until ($Choice -eq 'Q')