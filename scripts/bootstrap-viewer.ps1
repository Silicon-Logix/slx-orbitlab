# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Install the pinned official viewer engine inside the build cache.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$viewerPath=Join-Path $projectRoot 'build/tools/godot'
New-Item -ItemType Directory -Path $viewerPath -Force | Out-Null
$archivePath=Join-Path $viewerPath 'godot-4.5.zip'
$enginePath=Join-Path $viewerPath 'Godot_v4.5-stable_win64.exe'
$consolePath=Join-Path $viewerPath 'Godot_v4.5-stable_win64_console.exe'
if(-not (Test-Path -LiteralPath $enginePath) -or -not (Test-Path -LiteralPath $consolePath)) {
    $bundledViewer=Join-Path $projectRoot 'runtime/godot'
    if(Test-Path -LiteralPath (Join-Path $bundledViewer 'Godot_v4.5-stable_win64.exe')) {
        foreach($file in @('Godot_v4.5-stable_win64.exe','Godot_v4.5-stable_win64_console.exe')) {
            Copy-Item -LiteralPath (Join-Path $bundledViewer $file) -Destination $viewerPath -Force
        }
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/godotengine/godot-builds/releases/download/4.5-stable/Godot_v4.5-stable_win64.exe.zip' -OutFile $archivePath
        Expand-Archive -LiteralPath $archivePath -DestinationPath $viewerPath -Force
    }
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses/Godot-LICENSE.txt') -Destination (Join-Path $viewerPath 'LICENSE.txt') -Force
& $consolePath --headless --editor --path (Join-Path $projectRoot 'SLX_OrbitLab_3D') --import
if($LASTEXITCODE -ne 0){throw 'Godot import failed'}
Write-Output "Godot viewer ready: $enginePath"
