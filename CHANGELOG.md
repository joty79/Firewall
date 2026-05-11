# Changelog

## 2026-05-11

- Regenerated `Install.ps1` from the latest `InstallerCore` profile/template flow.
- Added `app-metadata.json` and wired the InstallerCore profile to deploy and verify it.
- Added `Launch-FirewallMenu.vbs` so Explorer context-menu launches go through a hidden elevated Windows Terminal handoff instead of flashing a brief first window.
- Updated the context-menu command/profile from direct `wt.exe ... FirewallMenu.ps1` launch to `wscript.exe "Launch-FirewallMenu.vbs" "%1"`.
- Added in-menu update status and an `Update app` action with commit-aware checks, git fallback metadata, stale `UpToDate` blocking, progress output, recent installer log output, failure display, and relaunch on success.
- Added active Windows Firewall profile status in the menu header and a warning after rule creation when the current profile firewall is disabled.
- Broadened profile cleanup coverage for legacy `FirewallMenu.ps1` application shell keys in HKCU/HKCR.
