[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$ResetStoreCache,
  [switch]$ReRegisterPackages,
  [string]$ProductId,
  [switch]$OpenStore,
  [int]$RecentMinutes = 15
)

$ErrorActionPreference = "Continue"

$StoreLoopbackPackages = @(
  "Microsoft.WindowsStore_8wekyb3d8bbwe",
  "Microsoft.StorePurchaseApp_8wekyb3d8bbwe",
  "Microsoft.DesktopAppInstaller_8wekyb3d8bbwe",
  "Microsoft.Services.Store.Engagement_8wekyb3d8bbwe"
)

$KnownBadLiteralNames = @('$pkg', '$m', '$sid')

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host "=== $Title ==="
}

function Test-IsAdmin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-SelfElevated {
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`""
  )
  if ($Apply) { $args += "-Apply" }
  if ($ResetStoreCache) { $args += "-ResetStoreCache" }
  if ($ReRegisterPackages) { $args += "-ReRegisterPackages" }
  if ($ProductId) { $args += @("-ProductId", $ProductId) }
  if ($OpenStore) { $args += "-OpenStore" }
  if ($RecentMinutes) { $args += @("-RecentMinutes", [string]$RecentMinutes) }

  Write-Host "Requesting Administrator elevation for CheckNetIsolation loopback repair..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args -Wait
}

function Get-InternetProxySettings {
  $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
  if (-not (Test-Path $key)) { return $null }
  Get-ItemProperty $key | Select-Object ProxyEnable, ProxyServer, ProxyOverride
}

function Get-ProxyPort {
  param([string]$ProxyServer)
  if (-not $ProxyServer) { return $null }
  $match = [regex]::Match($ProxyServer, "(127\.0\.0\.1|localhost|\[::1\]|::1):(?<port>\d+)")
  if ($match.Success) { return [int]$match.Groups["port"].Value }
  $fallback = [regex]::Match($ProxyServer, ":(?<port>\d+)(;|$)")
  if ($fallback.Success) { return [int]$fallback.Groups["port"].Value }
  return $null
}

function Show-StorePackages {
  Write-Section "Store packages"
  foreach ($name in "Microsoft.WindowsStore", "Microsoft.StorePurchaseApp", "Microsoft.DesktopAppInstaller") {
    Get-AppxPackage -Name $name -ErrorAction SilentlyContinue |
      Select-Object Name, PackageFamilyName, PackageFullName, Status, InstallLocation |
      Format-List
  }
}

function Show-StoreServices {
  Write-Section "Store services"
  Get-Service InstallService, ClipSVC, BITS, DoSvc, TokenBroker, WpnService, WpnUserService* -ErrorAction SilentlyContinue |
    Select-Object Name, DisplayName, Status, StartType |
    Format-Table -AutoSize
}

function Show-LoopbackExemptions {
  Write-Section "Loopback exemptions"
  & CheckNetIsolation.exe LoopbackExempt -s
}

function Repair-LoopbackExemptions {
  Write-Section "Applying loopback exemptions"
  foreach ($bad in $KnownBadLiteralNames) {
    & CheckNetIsolation.exe LoopbackExempt -d "-n=$bad" | Out-Null
  }
  foreach ($pkg in $StoreLoopbackPackages) {
    Write-Host "Adding $pkg"
    & CheckNetIsolation.exe LoopbackExempt -a "-n=$pkg" | Out-Null
  }
  Show-LoopbackExemptions
}

function Reset-StoreCache {
  Write-Section "Reset Store cache"
  Start-Process wsreset.exe -Wait
}

function Register-StorePackages {
  Write-Section "Re-register Store packages"
  Get-Process WinStore.App -ErrorAction SilentlyContinue | Stop-Process -Force
  foreach ($name in "Microsoft.WindowsStore", "Microsoft.StorePurchaseApp", "Microsoft.DesktopAppInstaller") {
    $pkg = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue
    if (-not $pkg) {
      Write-Warning "Package not found: $name"
      continue
    }
    $manifest = Join-Path $pkg.InstallLocation "AppxManifest.xml"
    if (Test-Path $manifest) {
      Write-Host "Registering $name"
      Add-AppxPackage -DisableDevelopmentMode -Register $manifest
    } else {
      Write-Warning "Manifest not found: $manifest"
    }
  }
}

function Show-StoreNetwork {
  param([int]$ProxyPort)
  Write-Section "WinStore.App TCP connections"
  $p = Get-Process WinStore.App -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $p) {
    Write-Host "WinStore.App is not running."
    return
  }
  $connections = Get-NetTCPConnection -OwningProcess $p.Id -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, RemoteAddress, RemotePort, State, AppliedSetting, CreationTime |
    Sort-Object CreationTime -Descending
  if ($ProxyPort) {
    $connections |
      Where-Object { $_.RemoteAddress -in "127.0.0.1", "::1" -or $_.RemotePort -eq $ProxyPort } |
      Format-Table -AutoSize
  } else {
    $connections | Select-Object -First 20 | Format-Table -AutoSize
  }
}

function Show-StoreLogs {
  param([int]$Minutes)
  Write-Section "Recent Store logs"
  $start = (Get-Date).AddMinutes(-1 * $Minutes)
  Get-WinEvent -FilterHashtable @{ LogName = "Microsoft-Windows-Store/Operational"; StartTime = $start } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match "0x80072EFD|CannotConnect|DataUnavailable|TransportException|StoreActivated|Store is starting|Corrupted" } |
    Select-Object TimeCreated, Id, LevelDisplayName,
      @{ Name = "ShortMessage"; Expression = {
        $text = $_.Message -replace "\s+", " "
        $text.Substring(0, [Math]::Min(420, $text.Length))
      }} |
    Format-List
}

function Test-StoreEndpoints {
  param([int]$ProxyPort)
  Write-Section "Endpoint reachability"
  $url = "https://storeedge.microsoft.com/v9.0/pages/home?market=US&locale=en-US&deviceFamily=Windows.Desktop"
  Write-Host "Direct:"
  & curl.exe -sS -I --connect-timeout 10 --max-time 20 --noproxy "*" $url
  if ($ProxyPort) {
    Write-Host ""
    Write-Host "Via local proxy 127.0.0.1:${ProxyPort}:"
    & curl.exe -sS -I --connect-timeout 10 --max-time 20 -x "http://127.0.0.1:$ProxyPort" $url
  }
}

if ($Apply -and -not (Test-IsAdmin)) {
  Invoke-SelfElevated
  Write-Host "Elevated repair process finished. Re-run diagnose mode to verify, or refresh Microsoft Store."
  exit
}

Write-Section "Current proxy"
$proxy = Get-InternetProxySettings
$proxy | Format-List
$proxyPort = Get-ProxyPort -ProxyServer $proxy.ProxyServer
if ($proxyPort) {
  Write-Host "Detected local/system proxy port: $proxyPort"
}

Show-StorePackages
Show-StoreServices
Show-LoopbackExemptions

if ($Apply) {
  Repair-LoopbackExemptions
}

if ($ResetStoreCache) {
  Reset-StoreCache
}

if ($ReRegisterPackages) {
  Register-StorePackages
}

if ($OpenStore -and $ProductId) {
  Write-Section "Open Store product"
  Get-Process WinStore.App -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 2
  Start-Process "ms-windows-store://pdp/?productid=$ProductId"
  Start-Sleep -Seconds 8
}

Show-StoreNetwork -ProxyPort $proxyPort
Show-StoreLogs -Minutes $RecentMinutes
Test-StoreEndpoints -ProxyPort $proxyPort

Write-Section "Summary"
if ($Apply) {
  Write-Host "Applied targeted loopback exemptions for Microsoft Store, Store Purchase, Desktop App Installer, and Store Engagement."
} else {
  Write-Host "Diagnose-only run. Add -Apply to repair Store/UWP loopback exemptions."
}
Write-Host "System proxy was not modified by this script."
