#Requires -Version 7
<#
Differential test: proves the C# report logic matches the QML service.

It runs the real QML functions under node and the C# implementation over the
same fixtures, then diffs every derived figure. The reference and the fixtures
are shared with the macOS test, so both ports are held to one behavior.

Run this after touching anything in src/Pomodoro.Core.
#>
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$repo = Split-Path $root -Parent
$work = Join-Path ([System.IO.Path]::GetTempPath()) "pomodoro-difftest-$PID"

foreach ($tool in 'node', 'python', 'dotnet') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is required"
    }
}

$idleState = @'
{"version":4,"phase":"focus","running":false,"endAt":0,
"remainingSeconds":1500,"completedFocus":0,"cycleDateKey":"","activeNote":"",
"phaseStartedAt":0,"phaseRunStartedAt":0,"phaseElapsedSeconds":0,
"phasePlannedSeconds":0,"phaseSegments":[],"phaseRang":false}
'@

New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
    Write-Host '==> Building'
    dotnet build (Join-Path $root 'Pomodoro.sln') -c Release --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw 'build failed' }

    $dump = Join-Path $root 'src/Pomodoro.ReportDump/bin/Release/net8.0/Pomodoro.ReportDump.dll'
    if (-not (Test-Path $dump)) { throw "report dump not found at $dump" }

    $status = 0
    foreach ($fixture in @('generated', 'hostile')) {
        $dir = Join-Path $work $fixture
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -Path (Join-Path $dir 'pomodoro.json') -Value $idleState -NoNewline

        python (Join-Path $repo 'tools/fixtures.py') $fixture $dir
        if ($LASTEXITCODE -ne 0) { throw 'fixture generation failed' }

        $reference = Join-Path $work "$fixture-reference.json"
        $actual = Join-Path $work "$fixture-windows.json"

        node (Join-Path $repo 'tools/qml-reference.js') $dir $reference | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'reference run failed' }

        $env:POMODORO_DATA_DIR = $dir
        dotnet $dump $actual | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'report dump failed' }

        Write-Host -NoNewline ("{0,-10} " -f $fixture)
        python (Join-Path $repo 'tools/compare-reports.py') $reference $actual
        if ($LASTEXITCODE -ne 0) { $status = 1 }
    }
    exit $status
}
finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
