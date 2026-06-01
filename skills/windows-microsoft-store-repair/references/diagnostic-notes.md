# Diagnostic Notes

## Common Evidence

- Store UI: "Check your connection" or "Microsoft Store needs to be online".
- Event log: `Microsoft-Windows-Store/Operational` with `0x80072EFD`, `WinStore.Network.TransportException`, `DataUnavailableException`, or `CannotConnect`.
- Store installer stub: Microsoft-signed `Store Installer` downloaded from `https://get.microsoft.com/installer/download/<product-id>`.
- UWP proxy failure: `WinStore.App` has TCP connections to `127.0.0.1:<proxy-port>` stuck in `SynSent`.
- UWP proxy fixed: the same connections become `Established`.

## Preserve User State

Before touching proxy settings:

```powershell
$backup = "$PWD\internet-settings-before-store-repair.reg"
reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" $backup /y
```

Avoid changing `ProxyServer` from `127.0.0.1:<port>` to a LAN IP unless the user explicitly wants a temporary experiment. It can trigger WSL proxy-change notifications and can affect tools that read the Windows system proxy.

Do not run `wsl --shutdown` just to clear the WSL notification unless the user confirms that stopping all WSL distros is acceptable.

## Useful Commands

Inspect a downloaded Store installer:

```powershell
Get-Item "C:\Users\$env:USERNAME\Downloads\Codex Installer.exe" -Stream *
Get-AuthenticodeSignature "C:\Users\$env:USERNAME\Downloads\Codex Installer.exe"
(Get-Item "C:\Users\$env:USERNAME\Downloads\Codex Installer.exe").VersionInfo
```

Extract the download source from `Zone.Identifier`:

```powershell
Get-Content "C:\path\to\Installer.exe" -Stream Zone.Identifier
```

Check packages:

```powershell
Get-AppxPackage -Name Microsoft.WindowsStore
Get-AppxPackage -Name Microsoft.StorePurchaseApp
Get-AppxPackage -Name Microsoft.DesktopAppInstaller
```

Check dependencies:

```powershell
Get-Service InstallService,ClipSVC,BITS,DoSvc,TokenBroker,WpnService,WpnUserService* -ErrorAction SilentlyContinue
```

Test Store endpoints direct and via local proxy:

```powershell
curl.exe -I --connect-timeout 10 --max-time 20 --noproxy "*" "https://storeedge.microsoft.com/v9.0/pages/home?market=US&locale=en-US&deviceFamily=Windows.Desktop"
curl.exe -I --connect-timeout 10 --max-time 20 -x http://127.0.0.1:7890 "https://storeedge.microsoft.com/v9.0/pages/home?market=US&locale=en-US&deviceFamily=Windows.Desktop"
```

## Correct Loopback Repair

Use `CheckNetIsolation.exe` from an elevated PowerShell. Quote the `-n=` argument when a variable is involved:

```powershell
$packages = @(
  "Microsoft.WindowsStore_8wekyb3d8bbwe",
  "Microsoft.StorePurchaseApp_8wekyb3d8bbwe",
  "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe",
  "Microsoft.Services.Store.Engagement_8wekyb3d8bbwe"
)

foreach ($pkg in $packages) {
  CheckNetIsolation.exe LoopbackExempt -a "-n=$pkg"
}
CheckNetIsolation.exe LoopbackExempt -s
```

If an earlier attempt created bad entries named `AppContainer NOT FOUND`, derive whether they came from a literal variable name:

```powershell
CheckNetIsolation.exe LoopbackExempt -d "-n=$pkg"
CheckNetIsolation.exe LoopbackExempt -d "-n=$m"
CheckNetIsolation.exe LoopbackExempt -d "-n=$sid"
CheckNetIsolation.exe LoopbackExempt -s
```

## Escalation Steps

Use these only after the targeted loopback repair and `wsreset.exe` fail.

Reset Store cache:

```powershell
Start-Process wsreset.exe -Wait
```

Re-register current-user Store packages:

```powershell
Get-Process WinStore.App -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($name in "Microsoft.WindowsStore","Microsoft.StorePurchaseApp","Microsoft.DesktopAppInstaller") {
  $pkg = Get-AppxPackage -Name $name
  if ($pkg -and (Test-Path "$($pkg.InstallLocation)\AppxManifest.xml")) {
    Add-AppxPackage -DisableDevelopmentMode -Register "$($pkg.InstallLocation)\AppxManifest.xml"
  }
}
```

Use SFC/DISM only if package registration or core Windows files appear corrupted; these are slower and broader repairs.
