---
name: windows-microsoft-store-repair
description: Diagnose and repair Windows Microsoft Store, App Installer, get.microsoft.com Store Installer, and UWP app connectivity failures, especially "Check your connection", "Microsoft Store needs to be online", 0x80072EFD, WinStore DataUnavailable/CannotConnect logs, Store product pages that will not open, and local proxy or 127.0.0.1 loopback issues affecting Store, Xbox, or Codex Microsoft Store installs. Use on Windows when a Microsoft-signed Store installer launches but Store cannot connect, download, update, or return online.
---

# Windows Microsoft Store Repair

## Core Rules

Protect the user's proxy setup first. Do not change `ProxyServer`, proxy ports, VPN/client rules, WSL networking, or Cloud Code configuration unless the user explicitly agrees. If a proxy change is unavoidable, export `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` first and restore it before finishing.

Prefer targeted UWP loopback repair over changing the system proxy. Microsoft Store and other UWP apps often honor a Windows proxy like `127.0.0.1:7890` but cannot connect to localhost until their AppContainer has a loopback exemption.

Do not shut down WSL, reset Microsoft Store app data, re-register packages, or click Store install/update buttons without a short action-time confirmation when that could interrupt running work or install software.

## Quick Workflow

1. Identify the symptom and current screen: Store "Check your connection", `0x80072EFD`, `CannotConnect`, `DataUnavailableException`, Store installer from `get.microsoft.com`, or a product URI such as `ms-windows-store://pdp/?productid=...`.
2. Run the bundled script in diagnose mode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\windows-microsoft-store-repair\scripts\repair-microsoft-store-uwp-proxy.ps1" -ProductId 9PLM9XGG6VKS
```

3. If diagnostics show Store/App Installer trying and failing to reach `127.0.0.1:<port>`, apply the loopback repair:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\skills\windows-microsoft-store-repair\scripts\repair-microsoft-store-uwp-proxy.ps1" -Apply -ResetStoreCache -ProductId 9PLM9XGG6VKS -OpenStore
```

4. Re-check Store logs and TCP connections. A repaired Store should show `WinStore.App` connections to `127.0.0.1:<proxy-port>` as `Established`, not `SynSent`.

## Manual Repair

Use these package family names for Store-related UWP loopback exemptions:

```text
Microsoft.WindowsStore_8wekyb3d8bbwe
Microsoft.StorePurchaseApp_8wekyb3d8bbwe
Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
Microsoft.Services.Store.Engagement_8wekyb3d8bbwe
```

When invoking `CheckNetIsolation.exe` from PowerShell, quote interpolated arguments:

```powershell
foreach ($pkg in $packages) {
  CheckNetIsolation.exe LoopbackExempt -a "-n=$pkg"
}
```

Do not write `-n=$pkg` unquoted. PowerShell can pass the literal string `$pkg` to native commands, creating an `AppContainer NOT FOUND` exemption for the wrong SID. If that happens, delete the bad literal names:

```powershell
CheckNetIsolation.exe LoopbackExempt -d "-n=$pkg"
CheckNetIsolation.exe LoopbackExempt -d "-n=$m"
CheckNetIsolation.exe LoopbackExempt -s
```

## Verification

Check current user proxy:

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
  Select-Object ProxyEnable,ProxyServer,ProxyOverride
```

Check Store event logs:

```powershell
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Store/Operational'; StartTime=(Get-Date).AddMinutes(-10)} |
  Where-Object { $_.Message -match '0x80072EFD|CannotConnect|DataUnavailable|StoreActivated' } |
  Select-Object TimeCreated,Id,LevelDisplayName,Message
```

Check whether Store is reaching the local proxy:

```powershell
$p = Get-Process WinStore.App -ErrorAction SilentlyContinue | Select-Object -First 1
if ($p) { Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue }
```

## Deeper Notes

Read `references/diagnostic-notes.md` when the quick script does not resolve the problem, when Store logs show new error codes, or when a prior attempted repair left bad loopback entries.
