# PROJECT_RULES

## Purpose

- Keep project-specific decisions for the `Firewall` repo here.

## Notes

- Add concise entries for critical fixes and installer/onboarding decisions.
- Runtime dependencies should live inside this workspace when the repo is onboarded to `InstallerCore`.

## Decision Log

### Entry - 2026-03-09 (InstallerCore onboarding)
- Date: 2026-03-09
- Problem: `Firewall` had only a script plus a manual `.reg` artifact with machine-local icon/script paths, so the context menu would not install cleanly on another PC or VM.
- Root cause: The repo was not onboarded to `InstallerCore`, and the runtime icon still lived outside the workspace.
- Guardrail/rule: Keep `Firewall` onboarded to `InstallerCore`. Runtime assets must stay in-repo under `.assets`, and `Install.ps1` must be regenerated from `InstallerCore` profile/template instead of hand-written.
- Files affected: `.assets\\icons\\firewall.ico`, `Install.ps1`, `README.md`, `PROJECT_RULES.md`.
- Validation/tests run: Profile generation via `InstallerCore\\scripts\\New-ToolInstaller.ps1`; PowerShell parser validation on generated `Install.ps1` and `FirewallMenu.ps1`.
