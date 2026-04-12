# RTV VR Mod Installer
# Copies built mod files to the correct locations in the game directory

param(
    [string]$BuildDir = "build",
    [string]$GameDir = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

Write-Host "=== RTV VR Mod Installer ===" -ForegroundColor Cyan
Write-Host "Game directory: $GameDir"
Write-Host "Build directory: $BuildDir"

# Verify game directory
if (-not (Test-Path "$GameDir\RTV.exe")) {
    Write-Error "RTV.exe not found in $GameDir. Is this the correct game directory?"
    exit 1
}

# Create directories
$dirs = @(
    "$GameDir\VR Mod\bin",
    "$GameDir\VR Mod\config",
    "$GameDir\VR Mod\logs"
)
foreach ($dir in $dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# Copy bootstrap DLL to game root
$bootstrapSrc = "$PSScriptRoot\..\$BuildDir\src\bootstrap\rtv_vr_bootstrap.dll"
if (Test-Path $bootstrapSrc) {
    Copy-Item $bootstrapSrc "$GameDir\rtv_vr_bootstrap.dll" -Force
    Write-Host "[OK] rtv_vr_bootstrap.dll" -ForegroundColor Green
} else {
    Write-Warning "rtv_vr_bootstrap.dll not found in build directory"
}

# Copy GDExtension DLL to game root
$modSrc = "$PSScriptRoot\..\$BuildDir\src\gdextension\librtv_vr_mod.windows.x86_64.dll"
if (Test-Path $modSrc) {
    Copy-Item $modSrc "$GameDir\librtv_vr_mod.windows.x86_64.dll" -Force
    Write-Host "[OK] librtv_vr_mod.windows.x86_64.dll" -ForegroundColor Green
} else {
    Write-Warning "librtv_vr_mod.windows.x86_64.dll not found in build directory"
}

# Copy injector
$injectorSrc = "$PSScriptRoot\..\$BuildDir\src\injector\rtv_vr_injector.exe"
if (Test-Path $injectorSrc) {
    Copy-Item $injectorSrc "$GameDir\VR Mod\bin\rtv_vr_injector.exe" -Force
    Write-Host "[OK] rtv_vr_injector.exe" -ForegroundColor Green
} else {
    Write-Warning "rtv_vr_injector.exe not found in build directory"
}

# Copy resources
Copy-Item "$PSScriptRoot\..\resources\override.cfg" "$GameDir\override.cfg" -Force
Write-Host "[OK] override.cfg" -ForegroundColor Green

Copy-Item "$PSScriptRoot\..\resources\rtv_vr_mod.gdextension" "$GameDir\rtv_vr_mod.gdextension" -Force
Write-Host "[OK] rtv_vr_mod.gdextension" -ForegroundColor Green

# Copy config files
Copy-Item "$PSScriptRoot\..\config\*" "$GameDir\VR Mod\config\" -Recurse -Force
Write-Host "[OK] Config files" -ForegroundColor Green

# Copy launch script
Copy-Item "$PSScriptRoot\launch_vr.bat" "$GameDir\launch_vr.bat" -Force
Write-Host "[OK] launch_vr.bat" -ForegroundColor Green

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host "Launch the game using launch_vr.bat in the game directory."
