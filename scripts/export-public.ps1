# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

param([string]$OutputDirectory='dist/SLX-OrbitLab-0.7.0-github',[string]$Distribution='Ubuntu-22.04',[switch]$IncludeSdk,[switch]$InitializeRepository)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$exportArguments=@("$projectRoot/tools/prepare-publication.py",'--output',$OutputDirectory,'--distribution',$Distribution)
if($IncludeSdk){$exportArguments+='--sdk'}
if($InitializeRepository){$exportArguments+='--git'}
& python -X utf8 @exportArguments
if($LASTEXITCODE -ne 0){throw 'Public export failed; inspect the audit result'}
