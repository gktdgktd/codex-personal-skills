param(
    [string]$CodexHome = (Join-Path $HOME ".codex")
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = Join-Path $CodexHome "skills"

if (-not (Test-Path -LiteralPath $sourceRoot)) {
    throw "Missing skills directory: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

Get-ChildItem -LiteralPath $sourceRoot -Directory | ForEach-Object {
    $target = Join-Path $targetRoot $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
    Write-Host "Installed skill: $($_.Name)"
}

Write-Host "Done. Restart Codex to reload skills."
