$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$QtCMakePath = $null

if ($env:QT_ROOT) {
    $candidate = Join-Path $env:QT_ROOT "bin\qt-cmake.bat"
    if (Test-Path $candidate) {
        $QtCMakePath = $candidate
    }
}

if (-not $QtCMakePath) {
    $command = Get-Command qt-cmake.bat -ErrorAction SilentlyContinue
    if ($command) {
        $QtCMakePath = $command.Source
    }
}

if (-not $QtCMakePath) {
    $file = Get-ChildItem -Path "C:\Qt" -Filter "qt-cmake.bat" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($file) {
        $QtCMakePath = $file.FullName
    }
}

if (-not $QtCMakePath) {
    throw "Qt 6 was not found. Install a Desktop Qt kit, or set QT_ROOT to its kit directory (for example C:\\Qt\\6.x.x\\mingw_64)."
}

$QtBin = Split-Path -Parent $QtCMakePath
$Build = Join-Path $Root "build-windows"
$Dist = Join-Path $Root "dist"
$CMakePath = $null
$command = Get-Command cmake.exe -ErrorAction SilentlyContinue
if ($command) {
    $CMakePath = $command.Source
}
if (-not $CMakePath) {
    $file = Get-ChildItem -Path "C:\Qt\Tools" -Filter "cmake.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($file) {
        $CMakePath = $file.FullName
    }
}
if (-not $CMakePath) {
    throw "CMake was not found. Install CMake, then rerun this script."
}

& $QtCMakePath -S $Root -B $Build -DCMAKE_BUILD_TYPE=Release
& $CMakePath --build $Build --config Release --parallel

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
