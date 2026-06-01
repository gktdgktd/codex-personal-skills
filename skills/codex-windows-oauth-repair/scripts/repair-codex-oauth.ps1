param(
  [switch]$Apply,
  [string]$BackupRoot
)

$ErrorActionPreference = 'Stop'

function Write-Step($Message) {
  Write-Host "==> $Message"
}

function Export-KeyIfExists($RegistryPath, $OutputPath) {
  $query = & reg.exe query $RegistryPath 2>$null
  if ($LASTEXITCODE -eq 0) {
    & reg.exe export $RegistryPath $OutputPath /y | Out-Null
    return $true
  }
  return $false
}

function Notify-AssociationsChanged {
  $code = @'
using System;
using System.Runtime.InteropServices;
public class CodexOAuthRepairShellNotify {
  [DllImport("shell32.dll")]
  public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
'@
  Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
  [CodexOAuthRepairShellNotify]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
}

if ($env:OS -notlike '*Windows*' -and -not $IsWindows) {
  throw 'This repair only applies to Windows.'
}

$pkg = Get-AppxPackage OpenAI.Codex -ErrorAction SilentlyContinue
if ($null -eq $pkg) {
  throw 'OpenAI.Codex MSIX package was not found. Reinstall or update Codex desktop first.'
}

$exe = Join-Path $pkg.InstallLocation 'app\Codex.exe'
$asar = Join-Path $pkg.InstallLocation 'app\resources\app.asar'
if (!(Test-Path -LiteralPath $exe)) {
  throw "Codex.exe not found at $exe"
}
if (!(Test-Path -LiteralPath $asar)) {
  throw "app.asar not found at $asar"
}

$capKey = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\$($pkg.PackageFullName)\App\Capabilities\URLAssociations"
$capReg = "HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\$($pkg.PackageFullName)\App\Capabilities"
$progId = $null
if (Test-Path -LiteralPath $capKey) {
  $progId = (Get-ItemProperty -LiteralPath $capKey -Name codex -ErrorAction SilentlyContinue).codex
}

$command = '"' + $exe + '" "' + $asar + '" "%1"'

Write-Step 'Codex package'
Write-Host "Package: $($pkg.PackageFullName)"
Write-Host "InstallLocation: $($pkg.InstallLocation)"
Write-Host "Codex.exe: $exe"
Write-Host "app.asar: $asar"
Write-Host "Desired command: $command"
Write-Host ""

Write-Step 'Current protocol state'
& reg.exe query HKCR\codex /s 2>$null
if ($progId) {
  Write-Host ""
  Write-Host "Package URLAssociation codex => $progId"
  & reg.exe query "HKCU\Software\Classes\$progId\Shell\open" /s 2>$null
} else {
  Write-Host "No package URLAssociation for codex was found under $capKey"
}

if (!$Apply) {
  Write-Host ""
  Write-Host "Diagnose-only mode. Re-run with -Apply to back up and repair the current user's registry handler."
  return
}

if ([string]::IsNullOrWhiteSpace($BackupRoot)) {
  $BackupRoot = Join-Path $env:USERPROFILE ".codex\backups\codex-oauth-repair"
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

Write-Step "Backing up registry keys to $backupDir"
Export-KeyIfExists 'HKCU\Software\Classes\codex' (Join-Path $backupDir 'codex-protocol.reg') | Out-Null
if ($progId) {
  Export-KeyIfExists "HKCU\Software\Classes\$progId" (Join-Path $backupDir 'appx-progid.reg') | Out-Null
}
Export-KeyIfExists $capReg (Join-Path $backupDir 'app-capabilities.reg') | Out-Null

Write-Step 'Repairing HKCU\Software\Classes\codex'
$codexBase = 'HKCU:\Software\Classes\codex'
if (Test-Path -LiteralPath $codexBase) {
  Remove-Item -LiteralPath $codexBase -Recurse -Force
}
New-Item -Path $codexBase -Force | Out-Null
Set-ItemProperty -Path $codexBase -Name '(default)' -Value 'URL:codex'
New-ItemProperty -Path $codexBase -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
New-Item -Path "$codexBase\DefaultIcon" -Force | Out-Null
Set-ItemProperty -Path "$codexBase\DefaultIcon" -Name '(default)' -Value "$exe,0"
New-Item -Path "$codexBase\Shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$codexBase\Shell\open\command" -Name '(default)' -Value $command

if ($progId) {
  Write-Step "Repairing AppX ProgID $progId"
  $progBase = "HKCU:\Software\Classes\$progId"
  $openKey = "$progBase\Shell\open"
  $cmdKey = "$openKey\command"
  New-Item -Path $cmdKey -Force | Out-Null
  foreach ($name in 'AppUserModelID','PackageRelativeExecutable','DesktopAppXActivateOptions','ContractId','DesiredInitialViewState','PackageId') {
    Remove-ItemProperty -Path $openKey -Name $name -ErrorAction SilentlyContinue
  }
  Remove-ItemProperty -Path $cmdKey -Name 'DelegateExecute' -ErrorAction SilentlyContinue
  Set-ItemProperty -Path $cmdKey -Name '(default)' -Value $command
  New-Item -Path "$progBase\Shell" -Force | Out-Null
  Set-ItemProperty -Path "$progBase\Shell" -Name '(default)' -Value 'open' -ErrorAction SilentlyContinue
}

Notify-AssociationsChanged

Write-Step 'Repaired protocol state'
& reg.exe query HKCR\codex /s
if ($progId) {
  Write-Host ""
  & reg.exe query "HKCR\$progId\Shell\open" /s
}
Write-Host ""
Write-Host "Backups written to: $backupDir"
Write-Host "Close stale OAuth/browser authorization tabs and retry the connector authorization from Codex."
