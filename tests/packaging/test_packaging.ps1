# tests/packaging/test_packaging.ps1
#
# Validates the build artifacts produced by build.bat.
# Run AFTER build.bat. Asserts:
#   - releases/vr-mod.vmz exists
#   - VMZ contains every expected resource at the right path
#   - Every VMZ entry path uses forward slashes (Metro rejects backslashes)
#   - Game root has no stale resources/vr_mod_init.gd shadowing the VMZ
#   - Native release DLLs exist and are at least as new as their sources
#   - resources/default_config.json matches config/default_config.json
#   - VMZ's vr_mod_init.gd matches the source on disk
#
# Exit code 0 on success, 1 if any assertion failed.
#
# All output is plain ASCII so Windows PowerShell 5.1 (Western European
# default codepage) parses the script correctly without a BOM.

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:Failures = @()
$script:Passes = 0

function Assert-True($cond, $msg) {
	if ($cond) {
		$script:Passes++
		Write-Host "  PASS: $msg"
	} else {
		$script:Failures += $msg
		Write-Host "  FAIL: $msg" -ForegroundColor Red
	}
}

function Section($name) {
	Write-Host ""
	Write-Host "== $name ==" -ForegroundColor Cyan
}

function Open-Vmz($vmzPath) {
	$fs = [System.IO.File]::OpenRead($vmzPath)
	return [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Read)
}

# Repo root = the parent of tests/
$ROOT = (Resolve-Path "$PSScriptRoot\..\..").Path
$VMZ  = Join-Path $ROOT "releases\vr-mod.vmz"
$FULL = Join-Path $ROOT "releases\vr-mod-full.zip"

Section "VMZ presence"
Assert-True (Test-Path $VMZ)  "vr-mod.vmz exists at $VMZ"
Assert-True (Test-Path $FULL) "vr-mod-full.zip exists at $FULL"

if (-not (Test-Path $VMZ)) {
	Write-Host ""
	Write-Host "FATAL: VMZ missing. Run build.bat first." -ForegroundColor Red
	exit 1
}

$zip = Open-Vmz $VMZ
try {
	$entries = $zip.Entries | ForEach-Object { $_.FullName }

	Section "VMZ entry paths use forward slashes"
	$bad = @($entries | Where-Object { $_ -match "\\" })
	Assert-True ($bad.Count -eq 0) "no entries contain backslashes (found $($bad.Count))"
	if ($bad.Count -gt 0) {
		$bad | ForEach-Object { Write-Host "    bad path: $_" }
	}

	Section "VMZ contains required entries"
	$required = @(
		"mod.txt",
		"resources/override.cfg",
		"resources/vr_mod_init.gd",
		"resources/default_config.json",
		"resources/controls.md",
		"resources/hands/Hand_Nails_low_L.gltf",
		"resources/hands/Hand_Nails_low_R.gltf",
		"resources/hands/hand_col.png"
	)
	foreach ($r in $required) {
		Assert-True ($entries -contains $r) "entry present: $r"
	}

	Section "VMZ ships every resources/vr_mod/*.gd"
	$srcModules = Get-ChildItem -Path (Join-Path $ROOT "resources\vr_mod") -Filter "*.gd" |
		Select-Object -ExpandProperty Name
	foreach ($m in $srcModules) {
		$expected = "resources/vr_mod/$m"
		Assert-True ($entries -contains $expected) "subsystem packaged: $expected"
	}

	Section "VMZ has no stray files"
	$expectedSet = New-Object System.Collections.Generic.HashSet[string]
	$null = $expectedSet.Add("mod.txt")
	$null = $expectedSet.Add("resources/override.cfg")
	$null = $expectedSet.Add("resources/vr_mod_init.gd")
	$null = $expectedSet.Add("resources/default_config.json")
	$null = $expectedSet.Add("resources/controls.md")
	$null = $expectedSet.Add("resources/hands/Hand_Nails_low_L.gltf")
	$null = $expectedSet.Add("resources/hands/Hand_Nails_low_R.gltf")
	$null = $expectedSet.Add("resources/hands/hand_col.png")
	foreach ($m in $srcModules) { $null = $expectedSet.Add("resources/vr_mod/$m") }
	$stray = @($entries | Where-Object { -not $expectedSet.Contains($_) })
	Assert-True ($stray.Count -eq 0) "no unexpected entries in VMZ"
	if ($stray.Count -gt 0) {
		$stray | ForEach-Object { Write-Host "    stray: $_" }
	}

	Section "VMZ vr_mod_init.gd matches source"
	$srcInit = Join-Path $ROOT "resources\vr_mod_init.gd"
	$initEntry = $zip.GetEntry("resources/vr_mod_init.gd")
	if ($null -eq $initEntry) {
		Assert-True $false "vr_mod_init.gd entry present in VMZ"
	} else {
		# Byte-level compare, not string compare. StreamReader's UTF-8
		# decoding can normalize sequences in ways that hide real drift,
		# while raw bytes catch any actual difference (including stale VMZ).
		$ms = New-Object System.IO.MemoryStream
		$es = $initEntry.Open()
		$es.CopyTo($ms)
		$es.Close()
		$vmzBytes = $ms.ToArray()
		$srcBytes = [System.IO.File]::ReadAllBytes($srcInit)
		$same = $false
		if ($vmzBytes.Length -eq $srcBytes.Length) {
			$same = $true
			for ($i = 0; $i -lt $vmzBytes.Length; $i++) {
				if ($vmzBytes[$i] -ne $srcBytes[$i]) { $same = $false; break }
			}
		}
		Assert-True $same "VMZ vr_mod_init.gd matches source on disk (byte-exact)"
	}
} finally {
	$zip.Dispose()
}

Section "Game root has no shadow autoload"
# Game root is the parent of "VR Mod". A copy of vr_mod_init.gd at
# <game>/resources/ would shadow the VMZ-mounted version and run stale code.
$gameRoot = Split-Path -Parent $ROOT
$shadow = Join-Path $gameRoot "resources\vr_mod_init.gd"
Assert-True (-not (Test-Path $shadow)) "no stale $shadow"

Section "Native artifacts present"
$bootstrap = Join-Path $ROOT "build\src\bootstrap\Release\rtv_vr_bootstrap.dll"
$gdext     = Join-Path $ROOT "build\src\gdextension\Release\librtv_vr_mod.windows.x86_64.dll"
$injector  = Join-Path $ROOT "build\src\injector\Release\rtv_vr_injector.exe"
Assert-True (Test-Path $bootstrap) "rtv_vr_bootstrap.dll built"
Assert-True (Test-Path $gdext)     "librtv_vr_mod.windows.x86_64.dll built"
Assert-True (Test-Path $injector)  "rtv_vr_injector.exe built"

Section "Native artifacts not stale vs sources"
function Test-Freshness($artifact, $sourceDir, $label) {
	if (-not (Test-Path $artifact)) {
		Assert-True $false "$label artifact missing"
		return
	}
	$artTime = (Get-Item $artifact).LastWriteTime
	$srcRoot = Join-Path $ROOT $sourceDir
	if (-not (Test-Path $srcRoot)) {
		Assert-True $true "$label source dir not found (skipping)"
		return
	}
	$newest = Get-ChildItem -Path $srcRoot -Recurse -File -ErrorAction SilentlyContinue |
		Where-Object { $_.Extension -in ".cpp",".h",".hpp",".c" } |
		Sort-Object LastWriteTime -Descending |
		Select-Object -First 1
	if (-not $newest) {
		Assert-True $true "$label has no C/C++ sources (skipping)"
		return
	}
	Assert-True ($artTime -ge $newest.LastWriteTime) "$label is newer than newest source ($($newest.Name))"
}
Test-Freshness $bootstrap "src\bootstrap"   "bootstrap"
Test-Freshness $gdext     "src\gdextension" "gdextension"
Test-Freshness $injector  "src\injector"    "injector"

Section "default_config.json consistency"
$bundled = Join-Path $ROOT "resources\default_config.json"
$ref     = Join-Path $ROOT "config\default_config.json"
Assert-True (Test-Path $bundled) "bundled defaults exist (resources/default_config.json)"
Assert-True (Test-Path $ref)     "reference defaults exist (config/default_config.json)"
if ((Test-Path $bundled) -and (Test-Path $ref)) {
	$bA = Get-Content $bundled -Raw | ConvertFrom-Json
	$rA = Get-Content $ref -Raw | ConvertFrom-Json
	$bJ = $bA | ConvertTo-Json -Depth 50 -Compress
	$rJ = $rA | ConvertTo-Json -Depth 50 -Compress
	Assert-True ($bJ -eq $rJ) "bundled and reference defaults parse-equal"
}

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "Packaging tests: $script:Passes passed, $($script:Failures.Count) failed"
if ($script:Failures.Count -gt 0) {
	Write-Host ""
	Write-Host "Failures:" -ForegroundColor Red
	$script:Failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
	exit 1
}
exit 0
