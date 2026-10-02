# Build Release MSIX for Plex Windows (x64).
# Prerequisites: .NET 8 SDK, Windows App SDK workload, Windows 10/11.
# Usage: pwsh -File scripts/pack-msix.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "Restoring..."
dotnet restore PlexWindows.sln

Write-Host "Building Release x64 (MSIX)..."
dotnet build src\PlexWindows\PlexWindows.csproj `
  -c Release `
  -p:Platform=x64 `
  -p:WindowsPackageType=MSIX `
  -p:GenerateAppxPackageOnBuild=true

$out = Get-ChildItem -Recurse -Filter *.msix -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match "AppPackages|bundle" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 5

if (-not $out) {
  Write-Host "No .msix found yet — check AppPackages under src\PlexWindows\bin."
  Get-ChildItem -Recurse src\PlexWindows\bin -ErrorAction SilentlyContinue | Select-Object -First 30 FullName
} else {
  Write-Host "MSIX outputs:"
  $out | ForEach-Object { Write-Host " - $($_.FullName)" }
}
