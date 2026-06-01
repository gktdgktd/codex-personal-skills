---
name: codex-windows-oauth-repair
description: Diagnose and repair Windows Codex desktop plugin OAuth callback failures where authorizing a connector such as Gmail, GitHub, Hugging Face, Google Drive, or Calendar opens an "Error launching app" dialog saying "Unable to find Electron app" or "Cannot find module" for a path containing oauth_callback, codex_scheme_oauth, or codex://connector/oauth_callback. Use on Windows when Codex plugin or connector authorization cannot return to the Codex app because the codex:// protocol handler or MSIX/AppX URL association is broken.
---

# Codex Windows OAuth Repair

## Overview

Repair Windows `codex://` deep-link handling for Codex desktop connector OAuth flows. The common failure is that Windows launches `Codex.exe codex://connector/oauth_callback?...`, and the Electron/Owl runtime treats the URL as the app path instead of loading the real `app.asar`.

## Workflow

1. Confirm the symptom before changing anything:
   - User sees an "Error launching app" dialog after approving a plugin connector.
   - Dialog contains `Unable to find Electron app`, `Cannot find module`, `oauth_callback`, `codex_scheme_oauth`, or `codex://connector/oauth_callback`.
   - The user is on Windows and Codex desktop is installed as `OpenAI.Codex`.

2. Run the bundled script in diagnose mode first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-oauth-repair\scripts\repair-codex-oauth.ps1"
```

3. Inspect the output:
   - If `OpenAI.Codex` is missing, tell the user to reinstall/update Codex desktop.
   - If `codex://` resolves through an AppX ProgID such as `AppX...` with `DelegateExecute`, `PackageRelativeExecutable`, or `ContractId=Windows.Protocol`, Windows may bypass the normal `HKCR\codex` command.
   - If command entries omit `app.asar` and pass only `%1`, the callback URL may become the first Electron positional argument and trigger the error.

4. Apply the repair only after explaining that it changes the current user's registry keys and writes backups:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\codex-windows-oauth-repair\scripts\repair-codex-oauth.ps1" -Apply
```

5. Ask the user to close old failed authorization tabs and retry the connector authorization from Codex.

## What The Repair Does

The script finds the installed `OpenAI.Codex` MSIX package, then locates:

- `app\Codex.exe`
- `app\resources\app.asar`
- the package URL association for `codex`
- the selected AppX ProgID, usually under `HKCU:\Software\Classes\AppX...`

When `-Apply` is set, it backs up the current registry entries to a timestamped directory and sets both the regular `codex` protocol key and the selected AppX ProgID to a command-based handler:

```text
"...\app\Codex.exe" "...\app\resources\app.asar" "%1"
```

It also removes AppX activation values from the selected ProgID's `Shell\open` branch so Windows does not keep using MSIX protocol activation that passes only the URL.

## Guardrails

- Do not use browser automation or Chrome as a workaround unless the user explicitly asks; this skill is for fixing the connector OAuth return path.
- Do not repeatedly trigger live `codex://connector/oauth_callback?...` tests while the user is seeing modal error dialogs. Prefer registry inspection, then ask the user to retry the actual connector flow once.
- Do not run `Add-AppxPackage -Register` as a first repair while Codex is open. It can fail with `0x80073D02`, and on affected builds it may restore the AppX handler that caused the bug.
- Do not delete unrelated AppX, file association, or browser keys.
- Keep backups of modified keys. Tell the user where they were written.

## References

Read [references/protocol-notes.md](references/protocol-notes.md) when you need the detailed diagnosis, registry paths, or rollback commands.
