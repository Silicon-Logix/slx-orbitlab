# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Rebuild both runtimes and execute meaningful local integration checks.
param([string]$Distribution='Ubuntu-22.04',[switch]$SkipBuild,[switch]$Campaign,[switch]$DesktopMission,[switch]$DesktopConsole,[switch]$DesktopSequences,[switch]$DesktopOrbits)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$orbitProjectRoot=Split-Path -Parent $PSScriptRoot
Push-Location $orbitProjectRoot
try {
    $orbitLinuxRoot=(& wsl.exe -d $Distribution -- wslpath -a -u $orbitProjectRoot.Replace('\','/')).Trim()
    $orbitBackendHome=(& wsl.exe -d $Distribution -- bash -lc 'printf %s "$HOME/.cache/slx-orbitlab"').Trim()
    if(-not $SkipBuild) {
        & wsl.exe -d $Distribution -- bash "$orbitLinuxRoot/scripts/build-backend.sh"
        if($LASTEXITCODE -ne 0){throw 'Linux flight deployment build failed'}
        & "$PSScriptRoot/build-windows.ps1"
    } else {
        & ctest --test-dir build/windows-mingw --output-on-failure
        if($LASTEXITCODE -ne 0){throw 'Desktop/core checks failed'}
    }
    & wsl.exe -d $Distribution -- "$orbitBackendHome/venv/bin/python" -m pytest tests/ -q
    if($LASTEXITCODE -ne 0){throw 'Physical integration checks failed'}
    & python tools/audit-source.py
    if($LASTEXITCODE -ne 0){throw 'Source/resource audit failed'}
    if($Campaign) {
        & wsl.exe -d $Distribution -- "$orbitBackendHome/venv/bin/python" tools/run-verification.py
        if($LASTEXITCODE -ne 0){throw 'Reference campaign failed'}
    }
    if($DesktopMission) {
        & python tools/check-desktop-runtime.py --extended --output validation/desktop-operations.json
        if($LASTEXITCODE -ne 0){throw 'Interactive desktop integration failed'}
    }
    if($DesktopConsole) {
        & python tools/check-desktop-runtime.py --console --extended --port 8879 --output validation/desktop-usability-0.7.0.json
        if($LASTEXITCODE -ne 0){throw 'Interactive command and Godot integration failed'}
    }
    if($DesktopSequences) {
        & python tools/check-desktop-runtime.py --sequences --port 8893 --output validation/desktop-sequences-0.7.0.json
        if($LASTEXITCODE -ne 0){throw 'Interactive sequencer and recording integration failed'}
    }
    if($DesktopOrbits) {
        & python tools/check-desktop-runtime.py --orbits --port 8897 --output validation/desktop-orbits-0.7.0.json
        if($LASTEXITCODE -ne 0){throw 'Guided orbital operation integration failed'}
    }
    Write-Output 'SLX OrbitLab integration checks passed.'
} finally {Pop-Location}
