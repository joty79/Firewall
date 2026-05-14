# Changelog

## 2026-05-14 (SystemTools Integration)

- Added no-target "Manager Only" mode: when launched from Desktop/Background with no file/folder, opens the interactive rule manager directly.
- Added large folder safety check: warns and asks confirmation if a folder contains more than 50 executables.
- Firewall Rules now integrated into SystemTools context menu under Windows submenu for all 4 contexts (file, folder, background, desktop).
- Old standalone registry entries (exefile/Directory FirewallManager) are cleaned up by SystemTools installer.

## 2026-05-14

- Bumped version to  .4.0.
- Integrated PS_UI_Blueprint.psm1 for a flicker-free, interactive Terminal UI (TUI).
- The Main Menu now uses arrow-key navigation instead of flat number inputs.
- Completely redesigned "Show All My Rules" (Menu 3) to be fully interactive:
  - Folders are shown as a selectable list.
  - Pressing Enter on a folder drills down into the specific .exe files affected within that folder.
  - Added interactive Toggle/Unblock support: You can now delete rules for an entire folder at once, or unblock specific .exe files individually.
  - Pressing Escape goes back to the previous menu, making it extremely easy to navigate large rule sets.
## 2026-05-14

- Bumped version to  .3.0.
- Added Folder Context Menu support in Install.ps1. Right-clicking a folder now allows blocking all executables inside it recursively.
- Refactored FirewallMenu.ps1 to detect if the target is a directory. If so, it scans for .exe files and blocks/unblocks them in bulk.
- Improved Show-All-My-Rules UI to group and display the rules beautifully under their respective folder paths instead of a flat list.
## 2026-05-14

- Bumped `app-metadata.json` to `0.2.2` and moved Firewall Rules back to the top-level `.exe` context menu instead of nesting it under `System Tools`.

## 2026-05-14

- Bumped `app-metadata.json` to `0.2.1` for the shared System Tools menu correction.
- Regenerated `Install.ps1` from `InstallerCore` so Firewall Rules installs under `System Tools > Windows` for `.exe` files.

## 2026-05-11

- Updated InstallerCore GitHub ref auto-detection priority so the explicit profile `github_ref` is preferred before remote/default `master`.
- Fixed the InstallerCore profile to use GitHub ref `master` so installs follow the repo's canonical default branch.
- Added an interactive installer failure pause through the latest InstallerCore template so errors remain visible with the installer log path instead of the window closing immediately.
- Regenerated `Install.ps1` from the latest `InstallerCore` profile/template flow.
- Added `app-metadata.json` and wired the InstallerCore profile to deploy and verify it.
- Added `Launch-FirewallMenu.vbs` so Explorer context-menu launches go through a hidden elevated Windows Terminal handoff instead of flashing a brief first window.
- Updated the context-menu command/profile from direct `wt.exe ... FirewallMenu.ps1` launch to `wscript.exe "Launch-FirewallMenu.vbs" "%1"`.
- Added in-menu update status and an `Update app` action with commit-aware checks against `master`, git fallback metadata, stale `UpToDate` blocking, progress output, recent installer log output, failure display, and relaunch on success.
- Added active Windows Firewall profile status in the menu header and a warning after rule creation when the current profile firewall is disabled.
- Broadened profile cleanup coverage for legacy `FirewallMenu.ps1` application shell keys in HKCU/HKCR.
