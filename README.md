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
| 🔒 | **[FirewallMenu.ps1](#-firewallmenups1)** | Elevated PowerShell menu that creates, removes, and inspects per-app firewall rules. |
| 🧩 | **[FirewallMenu.reg](#-firewallmenureg)** | Registry entry that adds the context-menu command for `.exe` files. |

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
        +--> Toggle inbound/outbound block rules
        +--> Deep scan by application filter path
        '--> Search/list rules created by this tool
```

This approach is faster than editing Windows Firewall manually because it keeps the workflow centered on the selected executable.

### Usage

**From Explorer** — *Right-click an `.exe` file and launch `Firewall Manager`.*

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

## 🧩 FirewallMenu.reg

> A Windows Registry artifact that adds the script to the `exefile` context menu.

### The Problem
- Running the script from terminal every time is less convenient than an Explorer verb.
- Explorer integration needs both a display name and a command target.
- Hardcoded local paths make a registry artifact non-portable across machines.

### The Solution

The `.reg` file creates a `Firewall Manager` shell command under `HKEY_CLASSES_ROOT\exefile\shell` and launches the PowerShell script through Windows Terminal. The current version still points to a machine-local icon and script path, so it should be treated as a development artifact until the repo is onboarded to `InstallerCore`.

```text
HKEY_CLASSES_ROOT\exefile\shell\FirewallManager
        |
        +--> Display name
        +--> Icon path
        '--> command
               |
               '--> wt.exe -- pwsh.exe -File FirewallMenu.ps1 -TargetItem "%1"
```

Using a `.reg` artifact keeps the Explorer integration simple, but portability requires repo-local assets and a generated installer.

## 📦 Installation

### Quick Setup
```powershell
# Clone locally
git clone https://github.com/joty79/Firewall.git

# Preferred: run the generated installer
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1

# One-off direct script test
pwsh -NoProfile -ExecutionPolicy Bypass -File .\FirewallMenu.ps1 -TargetItem "C:\Apps\Example\App.exe"
```

### Requirements

| Requirement | Details |
|-------------|---------|
| **OS** | Windows 10 or Windows 11 |
| **Runtime** | PowerShell 7 |
| **Privileges** | Administrator rights are required when managing firewall rules |
| **Explorer integration** | Windows Terminal (`wt.exe`) must be available for the current `.reg` command |

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
├── Install.ps1       # Generated InstallerCore-based installer entrypoint
├── FirewallMenu.ps1  # Interactive firewall rule manager
├── FirewallMenu.reg  # Explorer context-menu registration artifact
├── PROJECT_RULES.md  # Project-specific memory and guardrails
└── README.md         # You are here
```

## 🧠 Technical Notes

<details>
<summary><b>Why does the script relaunch itself as Administrator?</b></summary>

Managing Windows Firewall rules requires **elevated privileges**. The script checks the current token first and relaunches itself through **Windows Terminal** with `RunAs` when needed.

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

---

<p align="center">
  <sub>Built with PowerShell 7 · Explorer-driven workflow · Windows-only firewall automation</sub>
</p>
