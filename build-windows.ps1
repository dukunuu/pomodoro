$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$QtCMake = Get-ChildItem -Path "C:\Qt" -Filter "qt-cmake.bat" -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $QtCMake) {
    throw "Qt 6 was not found under C:\Qt. Install a Desktop Qt kit first."
}

$QtBin = Split-Path -Parent $QtCMake.FullName
$Build = Join-Path $Root "build-windows"
$Dist = Join-Path $Root "dist"

& $QtCMake.FullName -S $Root -B $Build -DCMAKE_BUILD_TYPE=Release
& cmake --build $Build --config Release --parallel

$Executable = Join-Path $Build "Release\pomodoro-windows.exe"
if (-not (Test-Path $Executable)) {
    $Executable = Join-Path $Build "pomodoro-windows.exe"
}
if (-not (Test-Path $Executable)) {
    throw "The Windows executable was not produced."
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
& (Join-Path $QtBin "windeployqt.exe") --release --qmldir (Join-Path $Root "qml") --no-translations $Executable
Copy-Item $Executable (Join-Path $Dist "pomodoro-windows.exe") -Force

Write-Host "Built: $Executable"
Write-Host "Run:   $Dist\pomodoro-windows.exe"
