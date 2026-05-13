# Changelog

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
