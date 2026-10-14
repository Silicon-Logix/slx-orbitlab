# Silicon LogiX / SLX OrbitLab
# Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
# Author: Marco Pezzullo
# License: Silicon LogiX Evaluation License 1.0. See LICENSE.

# Coordinate a hidden Linux service and the interactive Qt mission console.
param([string]$Distribution='Ubuntu-22.04',[string]$QtRoot='C:/Qt/6.12.0/mingw_64',[int]$Port=8765,[switch]$SkipBuild,[switch]$SmokeTest,[switch]$MissionTest)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$previousPath=$env:PATH
$serviceProcess=$null
$ownedService=$false
function Test-ServicePort {
    $probe=[Net.Sockets.TcpClient]::new()
    try {
        $pending=$probe.BeginConnect('127.0.0.1',$Port,$null,$null)
        if(-not $pending.AsyncWaitHandle.WaitOne(200)){return $false}
        $probe.EndConnect($pending)
        $stream=$probe.GetStream()
        $stream.ReadTimeout=700
        $requestId=[Guid]::NewGuid().ToString('N')
        $request=@{op='status';request_id=$requestId}|ConvertTo-Json -Compress
        $payload=[Text.Encoding]::UTF8.GetBytes($request+"`n")
        $stream.Write($payload,0,$payload.Length)
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$false,4096,$true)
        for($line=0;$line -lt 6;$line++) {
            $response=$reader.ReadLine()|ConvertFrom-Json
            if($response.type -eq 'reply' -and $response.request_id -eq $requestId){return $response.ok -and $response.data.schema -eq 'slx.orbitlab.service/1'}
        }
        return $false
    }
    catch {return $false}
    finally {$probe.Dispose()}
}
function Stop-OwnedService {
    $connection=[Net.Sockets.TcpClient]::new('127.0.0.1',$Port)
    try {
        $stream=$connection.GetStream()
        $stream.ReadTimeout=4000
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$false,4096,$true)
        foreach($operation in @('hello','shutdown')) {
            $requestId=[Guid]::NewGuid().ToString('N')
            $request=@{op=$operation;role='operator';request_id=$requestId}|ConvertTo-Json -Compress
            $payload=[Text.Encoding]::UTF8.GetBytes($request+"`n")
            $stream.Write($payload,0,$payload.Length)
            do {$reply=$reader.ReadLine()|ConvertFrom-Json} while($reply.type -ne 'reply' -or $reply.request_id -ne $requestId)
            if(-not $reply.ok){throw $reply.error}
        }
    } finally {$connection.Dispose()}
}
try {
    $env:PATH="$QtRoot/bin;C:/Qt/Tools/mingw1310_64/bin;$previousPath"
    $application=Join-Path $projectRoot 'build/windows-mingw/slx-orbitlab.exe'
    if(-not $SkipBuild -and -not (Test-Path -LiteralPath $application)){& "$PSScriptRoot/build-windows.ps1" -QtRoot $QtRoot}
    if(-not (Test-Path -LiteralPath $application)){throw 'Build the desktop console first'}
    if(-not (Test-ServicePort)) {
        $linuxRoot=(& wsl -d $Distribution -- wslpath -a -u $projectRoot.Replace('\','/')).Trim()
        New-Item -ItemType Directory -Path "$projectRoot/workspace" -Force | Out-Null
        $serviceProcess=Start-Process -FilePath 'wsl.exe' -ArgumentList @('-d',$Distribution,'--','bash',('"'+$linuxRoot+'/scripts/start-backend.sh"'),'--port',"$Port") -WindowStyle Hidden -PassThru -RedirectStandardOutput "$projectRoot/workspace/service.log" -RedirectStandardError "$projectRoot/workspace/service-errors.log"
        $ownedService=$true
        $ready=$false
        for($attempt=0;$attempt -lt 80;$attempt++){if(Test-ServicePort){$ready=$true;break}; if($serviceProcess.HasExited){throw 'Backend exited; inspect workspace/service-errors.log'}; Start-Sleep -Milliseconds 100}
        if(-not $ready){throw 'Backend startup timeout; run scripts/bootstrap-backend.sh and scripts/build-backend.sh in WSL'}
    }
    $consoleArguments=@('--root',('"'+$projectRoot+'"'),'--port',"$Port",'--distribution',$Distribution)
    $windowStyle='Normal'
    if($SmokeTest){$consoleArguments+='--smoke-test';$windowStyle='Hidden'}
    if($MissionTest){$consoleArguments+='--mission-test';$windowStyle='Normal'}
    $consoleProcess=Start-Process -FilePath $application -ArgumentList $consoleArguments -WindowStyle $windowStyle -PassThru
    $consoleProcess.WaitForExit()
    if($consoleProcess.ExitCode -ne 0){throw "Desktop console exited with code $($consoleProcess.ExitCode)"}
} finally {
    if($ownedService -and (Test-ServicePort)) {try {Stop-OwnedService} catch {Write-Warning "Backend shutdown: $_"}}
    $env:PATH=$previousPath
}
