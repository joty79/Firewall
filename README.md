<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows_10%2F11-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Platform">
  <img src="https://img.shields.io/badge/Language-PowerShell_7-5391FE?style=for-the-badge&logo=powershell&logoColor=white" alt="Language">
  <img src="https://img.shields.io/badge/License-Unspecified-green?style=for-the-badge" alt="License">
</p>

<h1 align="center">🔥 Firewall</h1>

<p align="center">
  <b>Interactive Windows Firewall rule manager for executable files.</b><br>
  <sub>Right-click an EXE, inspect its state, then block or restore network access in seconds.</sub>
</p>

## ✨ What's Inside

| # | Tool | Description |
|:-:|------|-------------|
| 🔒 | **[FirewallMenu.ps1](#-firewallmenups1)** | Elevated PowerShell menu that creates, removes, inspects, and updates per-app firewall tooling. |
| 👻 | **[Launch-FirewallMenu.vbs](#-launch-firewallmenuvbs)** | Hidden Explorer launcher that opens one elevated Windows Terminal session without the brief first-window flash. |
| 🧩 | **[FirewallMenu.reg](#-firewallmenureg)** | Legacy registry reference artifact kept for development history; the generated installer is the real install path. |

## 🔒 FirewallMenu.ps1

> A focused admin console for toggling inbound and outbound firewall blocks on a single executable.

### The Problem
- Windows Firewall rule inspection is slow when you only want to block or unblock one app.
- Manual rule creation is repetitive and easy to misname.
- It is hard to tell whether an executable is blocked by this tool or by some other rule source.

### The Solution

The script opens an elevated terminal, resolves the selected executable, and manages a dedicated pair of firewall rules using a predictable `_FW_BLOCK_` name prefix. It also offers a deep scan mode to detect unrelated rules that target the same executable path.

```text
Explorer context menu
        |
        v
 FirewallMenu.reg
        |
        v
 wt.exe + pwsh.exe
        |
        v
 FirewallMenu.ps1
        |
        +--> Fast status check by DisplayName prefix
        +--> Active firewall profile warning
        +--> Toggle inbound/outbound block rules
        +--> Deep scan by application filter path
        +--> Update app through InstallerCore/git
        '--> Search/list rules created by this tool
```

This approach is faster than editing Windows Firewall manually because it keeps the workflow centered on the selected executable.

The header also shows whether Windows Firewall is enabled for the active network profile. If the firewall is disabled, created block rules can still exist but Windows will not enforce them until the profile firewall is enabled again.

### Usage

**From Explorer** — *Open `System Tools > Windows > Firewall Rules` from file, folder, folder background, or desktop background context menus.*

**From terminal:**
```powershell
# Manage a specific executable
pwsh -NoProfile -ExecutionPolicy Bypass -File .\FirewallMenu.ps1 -TargetItem "C:\Apps\Example\App.exe"

# Use an absolute path directly
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\Users\joty79\scripts\Firewall\FirewallMenu.ps1" -TargetItem "C:\Tools\demo.exe"
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-TargetItem` | `string` | none | Full path to the target executable that should be inspected or blocked/unblocked. |

### Update App

The menu includes **Update app**. In an installed copy, it uses the generated `Install.ps1` backend with `UpdateGitHub`. In a git working copy, it uses a repo-aware `git fetch` plus `git pull --ff-only` path and refuses to update when local changes are present.

The update screen shows the current version, current commit, latest remote commit, progress output, recent installer log output, and failure exit codes. It does not reuse a stale `UpToDate` cache when a fresh remote check fails.

## 👻 Launch-FirewallMenu.vbs

> A hidden Explorer handoff that opens Firewall Manager directly in an elevated Windows Terminal host.

### The Problem
- Launching `wt.exe` directly from the registry could show a brief first window before the script relaunched elevated.
- Firewall rule changes require Administrator rights, so the final host must still be elevated.
- The selected `.exe` path must be passed safely through the context-menu command.

### The Solution

The registry command starts `wscript.exe`, and the VBS launcher uses `ShellExecute ... "runas"` to open `wt.exe` with the selected target. `FirewallMenu.ps1` then starts already elevated, so the visible experience is a single elevated terminal session.

```text
Explorer context menu
        |
        v
 wscript.exe Launch-FirewallMenu.vbs "%1"
        |
        v
 ShellExecute wt.exe ... "runas"
        |
        v
 FirewallMenu.ps1 -TargetItem "%1"
```

## 🧩 FirewallMenu.reg

> A legacy Windows Registry reference artifact retained for development history.

### The Problem
- Running the script from terminal every time is less convenient than an Explorer verb.
- Explorer integration needs both a display name and a command target.
- Hardcoded local paths make a registry artifact non-portable across machines.

### The Solution

The checked-in `.reg` file is no longer the installed Explorer path. The portable install flow comes from the generated `Install.ps1`, and the live entry is the shared `SystemTools > Windows > Firewall Rules` command family with `{InstallRoot}`-based paths plus cleanup for older standalone `FirewallManager` keys.

```text
System Tools
        |
        '--> Windows
               |
               '--> Firewall Rules
                      |
                      '--> wscript.exe Launch-FirewallMenu.vbs ...
```

The generated installer is the source of truth for install, update, uninstall, registry verification, and protected cleanup repair.

## 📦 Installation

### Quick Setup
```powershell
# Clone locally
git clone https://github.com/joty79/Firewall.git

# Preferred: run the generated installer
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1

# Update an installed copy from GitHub
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Action UpdateGitHub -Force -NoExplorerRestart

# One-off direct script test
pwsh -NoProfile -ExecutionPolicy Bypass -File .\FirewallMenu.ps1 -TargetItem "C:\Apps\Example\App.exe"
```

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 or Windows 11 |
| **Runtime** | PowerShell 7 |
| **Privileges** | Administrator rights are required when managing firewall rules |
| **Explorer integration** | Windows Terminal (`wt.exe`) is preferred; `pwsh.exe`, `wscript.exe`, and `reg.exe` are used by the install/launch flow |

## 📁 Project Structure

```text
Firewall/
├── .agents/
│   └── workflows/
│       └── readme.md # Local workflow metadata for README generation
├── .assets/
│   └── icons/
│       └── firewall.ico # Repo-owned icon used by the installed context menu
├── .gitignore        # Basic local ignores
├── app-metadata.json # App identity/version used by InstallerCore and update status
├── Install.ps1       # Generated InstallerCore-based installer entrypoint
├── FirewallMenu.ps1  # Interactive firewall rule manager
├── Launch-FirewallMenu.vbs # Hidden elevated Windows Terminal launcher
├── FirewallMenu.reg  # Explorer context-menu registration artifact
├── PROJECT_RULES.md  # Project-specific memory and guardrails
└── README.md         # You are here
```

## 🧠 Technical Notes

<details>
<summary><b>Why does the launcher use VBS?</b></summary>

Explorer context-menu commands can briefly flash a console when they call PowerShell or Windows Terminal directly. The VBS wrapper stays hidden and asks Windows to open the final `wt.exe` host elevated, so the visible path is a single Firewall Manager window.

</details>

<details>
<summary><b>Why does the script still check for Administrator?</b></summary>

Managing Windows Firewall rules requires **elevated privileges**. The VBS launcher normally starts the script elevated, but direct terminal runs are still supported, so the script keeps a fallback Administrator relaunch check.

</details>

<details>
<summary><b>Why are two firewall rules created for one app?</b></summary>

The script creates one rule for **Inbound** and one for **Outbound** traffic so the block is explicit in both directions. Both rules share the same `_FW_BLOCK_` prefix to make cleanup and search predictable.

</details>

<details>
<summary><b>Why is the current `.reg` file not portable yet?</b></summary>

The checked-in registry file is kept as a reference artifact, but the portable install path now comes from the generated `Install.ps1`. Runtime assets such as the icon live inside the repo, and the installer rewrites the deployed registry-facing paths to **`{InstallRoot}`-based locations**.

</details>

<details>
<summary><b>What does Deep Scan do differently from the fast status check?</b></summary>

The fast check only looks for rules by **DisplayName prefix**, which is nearly instant. Deep Scan inspects the **application filter path** on all firewall rules to detect matches created by other tools or manual configuration.

</details>

<details>
<summary><b>Why does the menu warn when Windows Firewall is disabled?</b></summary>

Firewall rules can be created successfully while the active Windows Firewall profile is disabled, but Windows will not enforce those rules until the profile firewall is enabled. The header warning makes that state visible before you wonder why a new block did not take effect.

</details>

---

<p align="center">
  <sub>Built with PowerShell 7 · Explorer-driven workflow · Windows-only firewall automation</sub>
</p>
