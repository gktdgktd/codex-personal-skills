# Protocol Notes

## Symptom

After the user approves a Codex connector authorization, Windows shows an Electron dialog:

```text
Error launching app
Unable to find Electron app at C:\Program ...\oauth_callback?code=...&state=codex_scheme_oauth...
Cannot find module 'C:\Program ...\oauth_callback?...'
```

The OAuth page is trying to open a deep link like:

```text
codex://connector/oauth_callback?code=...&state=codex_scheme_oauth...
```

## Root Cause

Codex's packaged app expects the Electron/Owl runtime to load the real app bundle first, then process command-line args for deep links. A broken Windows protocol association can launch:

```text
Codex.exe codex://connector/oauth_callback?...
```

In that shape, the callback URL is the first positional argument, so the runtime can treat it as the app path and search for an Electron app at `oauth_callback?...`.

On MSIX installs, Windows may ignore a repaired `HKCR\codex\Shell\open\command` and select the package URL association's AppX ProgID instead:

```text
HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\OpenAI.Codex_...\App\Capabilities\URLAssociations
  codex = AppX...

HKCU\Software\Classes\AppX...\Shell\open
```

The AppX ProgID may contain values such as:

```text
AppUserModelID
PackageRelativeExecutable = app\Codex.exe
DesktopAppXActivateOptions
ContractId = Windows.Protocol
DesiredInitialViewState
PackageId
Shell\open\command\DelegateExecute
```

Those values route through MSIX protocol activation and can keep passing only the deep-link URL.

## Correct Command Shape

For the affected Codex/Electron/Owl builds, use:

```text
"C:\Program Files\WindowsApps\OpenAI.Codex_...\app\Codex.exe" "C:\Program Files\WindowsApps\OpenAI.Codex_...\app\resources\app.asar" "%1"
```

The important part is that `app.asar` is the first positional argument and the `codex://...` URL is the second.

## Useful Registry Paths

Regular protocol key:

```text
HKCU\Software\Classes\codex
HKCR\codex
```

Package capability:

```text
HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\OpenAI.Codex_...\App\Capabilities\URLAssociations
```

Selected AppX ProgID:

```text
HKCU\Software\Classes\AppX...\Shell\open
HKCR\AppX...\Shell\open
```

## Rollback

Use the `.reg` files produced by the script's backup directory:

```powershell
reg import path\to\codex-protocol.reg
reg import path\to\appx-progid.reg
reg import path\to\app-capabilities.reg
```

If the app itself is stale or broken, a full Codex desktop update or reinstall may restore package defaults. On affected builds, that can also restore the broken protocol activation path, so re-run diagnose mode after updates.
