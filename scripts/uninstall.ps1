# RTV VR Mod Uninstaller
# Removes all mod files from the game directory, restoring it to vanilla state

param(
    [string]$GameDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

Write-Host "=== RTV VR Mod Uninstaller ===" -ForegroundColor Cyan
Write-Host "Game directory: $GameDir"

# Files to remove from game root
$filesToRemove = @(
    "$GameDir\rtv_vr_bootstrap.dll",
    "$GameDir\librtv_vr_mod.windows.x86_64.dll",
    "$GameDir\override.cfg",
    "$GameDir\rtv_vr_mod.gdextension",
    "$GameDir\launch_vr.bat"
)

foreach ($file in $filesToRemove) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-Host "[Removed] $(Split-Path -Leaf $file)" -ForegroundColor Yellow
    }
}

# Remove VR Mod bin and logs (keep config for user customizations)
$dirsToRemove = @(
    "$GameDir\VR Mod\bin",
    "$GameDir\VR Mod\logs"
)

foreach ($dir in $dirsToRemove) {
    if (Test-Path $dir) {
        Remove-Item $dir -Recurse -Force
        Write-Host "[Removed] $dir" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Uninstall Complete ===" -ForegroundColor Cyan
Write-Host "Note: VR Mod/config was preserved. Delete it manually if not needed."
