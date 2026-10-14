# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

param([string]$QtRoot='C:/Qt/6.12.0/mingw_64',[string]$ToolchainBin='C:/Qt/Tools/mingw1310_64/bin',[string]$BuildDirectory='build/windows-mingw')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$buildPath=Join-Path $projectRoot $BuildDirectory
$previousPath=$env:PATH
try {
    $env:PATH="$QtRoot/bin;$ToolchainBin;$previousPath"
    & cmake -S $projectRoot -B $buildPath -G Ninja "-DCMAKE_PREFIX_PATH=$QtRoot" "-DCMAKE_CXX_COMPILER=$ToolchainBin/g++.exe" -DCMAKE_BUILD_TYPE=Release
    if($LASTEXITCODE -ne 0){throw 'Configuration failed'}
    & cmake --build $buildPath --parallel 4
    if($LASTEXITCODE -ne 0){throw 'Build failed'}
    # Stage the runtime next to the executable, using the same Qt deployment tool as RadioTwin.
    $deploymentErrorPreference = $ErrorActionPreference
    try {
        # Windows PowerShell turns harmless native stderr into terminating errors.
        # The deploy tool's actual exit status decides whether staging succeeded.
        $ErrorActionPreference = 'Continue'
        & "$QtRoot/bin/windeployqt.exe" --release --compiler-runtime --no-translations --no-system-d3d-compiler --no-opengl-sw --skip-plugin-types qmltooling,generic --include-plugins qsvg,qsvgicon,qoffscreen --verbose 0 --qmldir "$projectRoot/qml" --dir $buildPath "$buildPath/slx-orbitlab.exe"
        $deploymentExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $deploymentErrorPreference }
    if($deploymentExitCode -ne 0){throw 'Qt runtime deployment failed'}
    $godotSource=Join-Path $projectRoot 'runtime/godot'
    if(-not (Test-Path -LiteralPath (Join-Path $godotSource 'Godot_v4.5-stable_win64.exe'))) {
        $godotSource=Join-Path $projectRoot 'build/tools/godot'
    }
    if(-not (Test-Path -LiteralPath (Join-Path $godotSource 'Godot_v4.5-stable_win64.exe'))) {
        & "$PSScriptRoot/bootstrap-viewer.ps1"
        $godotSource=Join-Path $projectRoot 'build/tools/godot'
    }
    $godotRuntime=Join-Path $buildPath 'runtime/godot'
    New-Item -ItemType Directory -Path $godotRuntime -Force | Out-Null
    foreach($file in @('Godot_v4.5-stable_win64.exe','Godot_v4.5-stable_win64_console.exe')) {
        Copy-Item -LiteralPath (Join-Path $godotSource $file) -Destination $godotRuntime -Force
    }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'licenses/Godot-LICENSE.txt') -Destination (Join-Path $godotRuntime 'LICENSE.txt') -Force
    & ctest --test-dir $buildPath --output-on-failure
    if($LASTEXITCODE -ne 0){throw 'Required checks failed'}
    $shortcutShell=New-Object -ComObject WScript.Shell
    $shortcut=$shortcutShell.CreateShortcut((Join-Path $projectRoot 'SLX OrbitLab.lnk'))
    $shortcut.TargetPath=Join-Path $buildPath 'slx-orbitlab.exe'
    $shortcut.Arguments=''
    $shortcut.WorkingDirectory=$projectRoot
    $shortcut.IconLocation=Join-Path $projectRoot 'assets/brand/orbitlab-icon.ico'
    $shortcut.Description='Silicon LogiX mission software and verification console'
    $shortcut.Save()
} finally {$env:PATH=$previousPath}
