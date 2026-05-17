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

### Entry - 2026-05-11 (Installer GitHub ref must stay on master)
- Date: 2026-05-11
- Problem: Interactive install downloaded `https://codeload.github.com/joty79/Firewall/zip/refs/heads/master` and failed with `Downloaded package does not contain required files.`
- Root cause: New local work had landed on `main` while the GitHub repository's canonical/default branch is `master`, so the remote `master` package was stale.
- Guardrail/rule: Keep `github_ref` explicitly set to `master` in the Firewall InstallerCore profile, `app-metadata.json`, and in-app update checks. InstallerCore GitHub ref auto-detection must prefer explicit profile `github_ref` before remote/default branch guesses.
- Files affected: `D:\\Users\\joty79\\scripts\\InstallerCore\\profiles\\Firewall.json`, `D:\\Users\\joty79\\scripts\\InstallerCore\\templates\\Install.Template.ps1`, `Install.ps1`, `CHANGELOG.md`, `PROJECT_RULES.md`.
- Validation/tests run: Regenerated `Install.ps1` from InstallerCore; parser validation on generated installer and InstallerCore template; static verification that embedded `github_ref` is `master` and auto-detection prioritizes profile ref before branch guesses.

### Entry - 2026-03-09 (InstallerCore onboarding)
- Date: 2026-03-09
- Problem: `Firewall` had only a script plus a manual `.reg` artifact with machine-local icon/script paths, so the context menu would not install cleanly on another PC or VM.
- Root cause: The repo was not onboarded to `InstallerCore`, and the runtime icon still lived outside the workspace.
- Guardrail/rule: Keep `Firewall` onboarded to `InstallerCore`. Runtime assets must stay in-repo under `.assets`, and `Install.ps1` must be regenerated from `InstallerCore` profile/template instead of hand-written.
- Files affected: `.assets\\icons\\firewall.ico`, `Install.ps1`, `README.md`, `PROJECT_RULES.md`.
- Validation/tests run: Profile generation via `InstallerCore\\scripts\\New-ToolInstaller.ps1`; PowerShell parser validation on generated `Install.ps1` and `FirewallMenu.ps1`.

### Entry - 2026-05-14 (Shared System Tools Windows category)

- Date: 2026-05-14
- Problem: The shared category formerly named `Apps & Windows` was renamed to `Windows`.
- Root cause: The visible menu needed a shorter and broader category name for Windows/app utilities.
- Guardrail/rule: `Firewall` remains child-only under `SystemTools\shell\Windows\shell\FirewallManager` for `exefile` branches. Keep cleanup for old `AppsWindows` child paths during migration.
- Files affected: `Install.ps1`, `app-metadata.json`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\Firewall.json`.
- Validation/tests run: Pending parser validation, local-source install, and HKCU registry readback after regeneration.

### Entry - 2026-05-17 (SystemTools-only live Firewall verb)

- Date: 2026-05-17
- Problem: Old standalone `FirewallManager` verbs for `.exe` files and folders still existed live alongside the shared `SystemTools` entry.
- Root cause: The `Firewall` generated installer/profile continued to define top-level `HKCU\Software\Classes\exefile\shell\FirewallManager`, and stale generated output still carried `Directory\shell\FirewallManager`.
- Guardrail/rule: `Firewall` must not install any live top-level `FirewallManager` verbs. Keep only cleanup for old `exefile`/`Directory` `FirewallManager` keys; the supported Explorer entrypoint is the shared `SystemTools > Windows > Firewall Rules` menu.
- Files affected: `Install.ps1`, `app-metadata.json`, `README.md`, `CHANGELOG.md`, `PROJECT_RULES.md`, `D:\Users\joty79\scripts\InstallerCore\profiles\Firewall.json`, `D:\Users\joty79\scripts\InstallerCore\PROJECT_RULES.md`.
- Validation/tests run: Pending regeneration, parser validation, local-source update, and HKCU registry readback.
