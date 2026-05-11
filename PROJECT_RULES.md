# PROJECT_RULES

## Purpose

- Keep project-specific decisions for the `Firewall` repo here.

## Notes

- Add concise entries for critical fixes and installer/onboarding decisions.
- Runtime dependencies should live inside this workspace when the repo is onboarded to `InstallerCore`.

## Decision Log

### Entry - 2026-05-11 (InstallerCore refresh, update UI, and hidden launcher)
- Date: 2026-05-11
- Problem: Explorer context-menu launch could briefly open an intermediate window before the elevated Firewall Manager host appeared, update state was not visible in the app menu, and users could create block rules while the active Windows Firewall profile was disabled without seeing why enforcement did not happen.
- Root cause: The registry command launched `wt.exe` directly, `FirewallMenu.ps1` had no app-side InstallerCore update UI/status contract, and the menu only checked tool-owned rules rather than the active firewall profile state.
- Guardrail/rule: Keep `Firewall` on the classic InstallerCore profile/template flow. Context-menu launch should go through `Launch-FirewallMenu.vbs` with `ShellExecute ... runas` so the visible host is a single elevated WT session. The menu must show active firewall profile status, expose `Update app`, block stale `UpToDate` fallback on fresh remote-check failure, and use the generated `Install.ps1` or git fast-forward path for updates.
- Files affected: `FirewallMenu.ps1`, `Launch-FirewallMenu.vbs`, `app-metadata.json`, `FirewallMenu.reg`, `Install.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\\Users\\joty79\\scripts\\InstallerCore\\profiles\\Firewall.json`.
- Validation/tests run: `InstallerCore\\scripts\\New-ToolInstaller.ps1` regeneration; PowerShell parser validation for `FirewallMenu.ps1`, generated `Install.ps1`, and `InstallerCore\\scripts\\New-ToolInstaller.ps1`; JSON validation for `InstallerCore\\profiles\\Firewall.json` and `app-metadata.json`; static verification for `RegistryRepair`, `EncodedCommand`, `NoSelfRelaunch`, `github_commit`, VBS launcher registry command, update UI strings, and firewall-disabled warning.

### Entry - 2026-03-09 (InstallerCore onboarding)
- Date: 2026-03-09
- Problem: `Firewall` had only a script plus a manual `.reg` artifact with machine-local icon/script paths, so the context menu would not install cleanly on another PC or VM.
- Root cause: The repo was not onboarded to `InstallerCore`, and the runtime icon still lived outside the workspace.
- Guardrail/rule: Keep `Firewall` onboarded to `InstallerCore`. Runtime assets must stay in-repo under `.assets`, and `Install.ps1` must be regenerated from `InstallerCore` profile/template instead of hand-written.
- Files affected: `.assets\\icons\\firewall.ico`, `Install.ps1`, `README.md`, `PROJECT_RULES.md`.
- Validation/tests run: Profile generation via `InstallerCore\\scripts\\New-ToolInstaller.ps1`; PowerShell parser validation on generated `Install.ps1` and `FirewallMenu.ps1`.
