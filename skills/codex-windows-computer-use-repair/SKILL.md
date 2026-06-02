---
name: codex-windows-computer-use-repair
description: Diagnose and repair Windows Codex desktop failures where Computer Use is unavailable, new chats cannot get desktop control, the native pipe path is missing, or logs show "Windows Computer Use helper paths are unavailable", "missing-helper-path", "Computer Use native pipe path is unavailable", "SKY_CUA_NATIVE_PIPE_DIRECTORY" missing, or bundled marketplace EBUSY locks involving Chrome extension-host.
---

# Codex Windows Computer Use Repair

## Overview

Use this skill when Codex Desktop on Windows has the Computer Use plugin installed but Computer Use cannot start or new chats report that desktop/computer permissions are unavailable. The common failure is that the bundled plugin marketplace did not reconcile fully, often because a stale Chrome native messaging `extension-host.exe` locked the temporary bundled marketplace, leaving the Computer Use helper path unavailable.

Prefer the normal `computer-use` skill bootstrap first when it is available and has not already failed. If `sky.list_apps()` succeeds, stop; Computer Use is working.

## Failure Signals

Treat these as strong indicators for this workflow:

- Tool setup reports `Computer Use native pipe path is unavailable`.
- Logs contain `Windows Computer Use helper paths are unavailable`.
- Logs contain `computer-use notify config ensure finished ... reason=missing-helper-path status=skipped`.
- The JavaScript runtime lacks `SKY_CUA_NATIVE_PIPE_DIRECTORY` when the Computer Use client expects it.
- Logs contain `bundled_plugins_marketplace_resolve_failed` with `EBUSY` while removing `.codex\.tmp\bundled-marketplaces\openai-bundled\plugins\chrome\extension-host\windows\x64`.
- `~\.codex\.tmp\bundled-marketplaces\openai-bundled\plugins` contains only some bundled plugins, for example `chrome` but not `computer-use`.
- A stale `extension-host.exe` under `.codex\plugins\cache\openai-bundled\chrome\...` predates the current Codex run.

## Diagnose

Use PowerShell diagnostics. Do not use Computer Use to automate the Codex Desktop UI while repairing Computer Use.

Find recent relevant log lines:

```powershell
$logRoot = Join-Path $env:LOCALAPPDATA 'Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\Codex\Logs'
rg -n "computer-use native pipe|Windows Computer Use helper paths|missing-helper-path|bundled_plugins_marketplace|EBUSY|SKY_CUA_NATIVE_PIPE_DIRECTORY" $logRoot
```

Inspect bundled plugin cache and temporary marketplace:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
Get-ChildItem -LiteralPath (Join-Path $codexHome 'plugins\cache\openai-bundled\computer-use') -Directory -ErrorAction SilentlyContinue |
  Select-Object Name, FullName, LastWriteTime
Get-ChildItem -LiteralPath (Join-Path $codexHome '.tmp\bundled-marketplaces\openai-bundled\plugins') -Directory -ErrorAction SilentlyContinue |
  Select-Object Name, FullName, LastWriteTime
```

Inspect helper and native-host processes:

```powershell
Get-CimInstance Win32_Process |
  Where-Object { $_.Name -in @('extension-host.exe', 'codex-computer-use.exe', 'node_repl.exe', 'node.exe') } |
  Select-Object Name, ProcessId, ParentProcessId, CreationDate, CommandLine |
  Format-List
```

The usual culprit is a stale Chrome native host:

```text
...\ .codex\plugins\cache\openai-bundled\chrome\latest\extension-host\windows\x64\extension-host.exe
```

## Repair

Only restart Codex Desktop after the user has asked for or approved a restart. The restart interrupts active Codex windows and helper processes.

Use one hidden PowerShell helper so Codex can terminate itself and relaunch cleanly. Keep deletion limited to the exact temporary bundled marketplace path after resolving and validating it.

```powershell
$script = @'
$ErrorActionPreference = "Continue"
$log = Join-Path $env:TEMP "codex-desktop-computer-use-repair.log"
function Write-RepairLog($message) {
  Add-Content -LiteralPath $log -Value "[$((Get-Date).ToString("o"))] $message"
}

Start-Sleep -Seconds 2
Write-RepairLog "restart requested"

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$tmpMarketplace = Join-Path $codexHome ".tmp\bundled-marketplaces\openai-bundled"
$resolvedTmp = [System.IO.Path]::GetFullPath($tmpMarketplace)
$expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $codexHome ".tmp\bundled-marketplaces"))

$staleHosts = Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -eq "extension-host.exe" -and
    ($_.CommandLine -like "*\.codex\plugins\cache\openai-bundled\chrome\*" -or
     $_.CommandLine -like "*chrome-extension://*")
  }
if ($staleHosts) {
  Write-RepairLog ("stopping stale chrome native hosts: " + (($staleHosts | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ", "))
  $staleHosts | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Seconds 1
}

if ($resolvedTmp.StartsWith($expectedRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
    (Test-Path -LiteralPath $resolvedTmp)) {
  Write-RepairLog "removing tmp marketplace: $resolvedTmp"
  Remove-Item -LiteralPath $resolvedTmp -Recurse -Force -ErrorAction SilentlyContinue
}

$codexProcesses = Get-CimInstance Win32_Process |
  Where-Object {
    $_.Name -in @("Codex.exe", "codex.exe", "node_repl.exe", "node.exe") -and
    (
      $_.ExecutablePath -like "$env:LOCALAPPDATA\OpenAI\Codex\*" -or
      $_.ExecutablePath -like "C:\Program Files\WindowsApps\OpenAI.Codex_*" -or
      $_.CommandLine -like "*OpenAI.Codex_*"
    )
  }
if ($codexProcesses) {
  Write-RepairLog ("stopping codex processes: " + (($codexProcesses | ForEach-Object { "$($_.Name):$($_.ProcessId)" }) -join ", "))
  $codexProcesses | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

Start-Sleep -Seconds 3
Start-Process explorer.exe "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
Write-RepairLog "start command issued"
'@

$path = Join-Path $env:TEMP "codex-desktop-computer-use-repair.ps1"
Set-Content -LiteralPath $path -Value $script -Encoding UTF8
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $path
```

If a previous restart happened before killing the stale `extension-host.exe`, one second restart with the cleanup-first ordering above is reasonable. Do not keep restarting after the same failure repeats; collect the latest error and report it.

## Verify

After Codex relaunches, verify all three layers:

1. Logs show bundled marketplace reconciliation with `browser`, `chrome`, `computer-use`, and `latex`.
2. Logs show `computer-use notify config ensure finished ... status=repaired` or `status=already-present`, followed by `computer-use native pipe startup ready pipePath=...`.
3. The current Computer Use plugin version can run a lightweight app listing.

Find the current plugin version dynamically. Do not reuse an old hard-coded version after restart:

```powershell
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
Get-ChildItem -LiteralPath (Join-Path $codexHome 'plugins\cache\openai-bundled\computer-use') -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 Name, FullName
```

Then run the normal Computer Use bootstrap against that `scripts\computer-use-client.mjs` path and call:

```js
globalThis.apps = await sky.list_apps();
nodeRepl.write(JSON.stringify({ ok: true, appCount: apps.length }, null, 2));
```

Any non-error response from `list_apps()` means the Windows helper and native pipe are reachable.

## Report

When fixed, state the concrete evidence:

- whether `sky.list_apps()` succeeded,
- the current Computer Use plugin version path,
- whether `codex-computer-use.exe` is running,
- the repaired log line or native pipe ready line.

When not fixed, report the newest exact setup error and the newest relevant log lines. Avoid summarizing stale errors from before the restart as if they are still current.
