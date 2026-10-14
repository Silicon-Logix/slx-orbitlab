@echo off
rem Silicon LogiX / SLX OrbitLab
rem Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
rem Author: Marco Pezzullo
rem License: Silicon LogiX Evaluation License 1.0. See LICENSE.
rem Launch the coordinated Windows console and Linux mission service.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\start-orbitlab.ps1" %*
if errorlevel 1 (
    echo OrbitLab could not start. Check the setup instructions in README.md.
    pause
    exit /b 1
)
