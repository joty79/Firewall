# PROJECT_RULES

## Purpose

- Keep project-specific decisions for the `Firewall` repo here.

## Notes

- Add concise entries for critical fixes and installer/onboarding decisions.
- Runtime dependencies should live inside this workspace when the repo is onboarded to `InstallerCore`.

## Decision Log

### Entry - 2026-05-11 (InstallerCore refresh, update UI, and hidden launcher)
- Date: 2026-05-11
- Problem: Explorer context-menu launch could briefly open an intermediate window before the elevated Firewall Manager host appeared, update state was not visible in the app menu, installer failures could close transient launch windows before the error was readable, and users could create block rules while the active Windows Firewall profile was disabled without seeing why enforcement did not happen.
- Root cause: The registry command launched `wt.exe` directly, `FirewallMenu.ps1` had no app-side InstallerCore update UI/status contract, generated installer actions exited immediately on non-zero interactive failures, and the menu only checked tool-owned rules rather than the active firewall profile state.
- Guardrail/rule: Keep `Firewall` on the classic InstallerCore profile/template flow. Context-menu launch should go through `Launch-FirewallMenu.vbs` with `ShellExecute ... runas` so the visible host is a single elevated WT session. Generated interactive installer failures must pause with exit code and log path. The menu must show active firewall profile status, expose `Update app`, block stale `UpToDate` fallback on fresh remote-check failure, and use the generated `Install.ps1` or git fast-forward path for updates.
- Files affected: `FirewallMenu.ps1`, `Launch-FirewallMenu.vbs`, `app-metadata.json`, `FirewallMenu.reg`, `Install.ps1`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\\Users\\joty79\\scripts\\InstallerCore\\profiles\\Firewall.json`, `D:\\Users\\joty79\\scripts\\InstallerCore\\templates\\Install.Template.ps1`.
- Validation/tests run: `InstallerCore\\scripts\\New-ToolInstaller.ps1` regeneration; PowerShell parser validation for `FirewallMenu.ps1`, generated `Install.ps1`, `InstallerCore\\templates\\Install.Template.ps1`, and `InstallerCore\\scripts\\New-ToolInstaller.ps1`; JSON validation for `InstallerCore\\profiles\\Firewall.json` and `app-metadata.json`; static verification for `RegistryRepair`, `EncodedCommand`, `NoSelfRelaunch`, `github_commit`, VBS launcher registry command, update UI strings, interactive failure pause, and firewall-disabled warning.

### Entry - 2026-05-11 (Installer GitHub ref must stay on main)
- Date: 2026-05-11
- Problem: Interactive install downloaded `https://codeload.github.com/joty79/Firewall/zip/refs/heads/master` and failed with `Downloaded package does not contain required files.`
- Root cause: `InstallerCore\\profiles\\Firewall.json` left `github_ref` empty while the repo's active/default branch is `main`, allowing the installer fallback path to try obsolete `master`.
- Guardrail/rule: Keep `github_ref` explicitly set to `main` in the Firewall InstallerCore profile and aligned with `app-metadata.json`.
- Files affected: `D:\\Users\\joty79\\scripts\\InstallerCore\\profiles\\Firewall.json`, `Install.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from InstallerCore; parser validation on generated installer; static verification that embedded `github_ref` is `main`.

### Entry - 2026-03-09 (InstallerCore onboarding)
- Date: 2026-03-09
- Problem: `Firewall` had only a script plus a manual `.reg` artifact with machine-local icon/script paths, so the context menu would not install cleanly on another PC or VM.
- Root cause: The repo was not onboarded to `InstallerCore`, and the runtime icon still lived outside the workspace.
- Guardrail/rule: Keep `Firewall` onboarded to `InstallerCore`. Runtime assets must stay in-repo under `.assets`, and `Install.ps1` must be regenerated from `InstallerCore` profile/template instead of hand-written.
- Files affected: `.assets\\icons\\firewall.ico`, `Install.ps1`, `README.md`, `PROJECT_RULES.md`.
- Validation/tests run: Profile generation via `InstallerCore\\scripts\\New-ToolInstaller.ps1`; PowerShell parser validation on generated `Install.ps1` and `FirewallMenu.ps1`.
