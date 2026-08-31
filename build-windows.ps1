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
$QtKit = Split-Path -Parent $QtBin
$QtRoot = Split-Path -Parent (Split-Path -Parent $QtKit)
$QtTools = Join-Path $QtRoot "Tools"
$env:Path = "$QtBin;$env:Path"

$CMakePath = $null
$command = Get-Command cmake.exe -ErrorAction SilentlyContinue
if ($command) {
    $CMakePath = $command.Source
}
if (-not $CMakePath) {
    $file = Get-ChildItem -Path $QtTools -Filter "cmake.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($file) {
        $CMakePath = $file.FullName
    }
}
if (-not $CMakePath) {
    throw "CMake was not found. Install CMake, then rerun this script."
}
$env:Path = "$(Split-Path -Parent $CMakePath);$env:Path"

# A Qt MinGW kit needs its matching compiler and make tool explicitly selected;
# otherwise CMake commonly falls back to an unusable NMake generator.
$MingwBin = $null
if ($QtKit -match "mingw") {
    $compiler = Get-ChildItem -Path $QtTools -Filter "g++.exe" -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($compiler) {
        $MingwBin = Split-Path -Parent $compiler.FullName
    }
    if (-not $MingwBin -or -not (Test-Path (Join-Path $MingwBin "mingw32-make.exe"))) {
        throw "The Qt MinGW kit was found, but its MinGW compiler was not. Add the MinGW 64-bit compiler in Qt Maintenance Tool."
    }
    $env:Path = "$MingwBin;$env:Path"
}

$Build = Join-Path $Root "build-windows"
$Dist = Join-Path $Root "dist"

$ConfigureArgs = @("-S", $Root, "-B", $Build, "-DCMAKE_BUILD_TYPE=Release")
if ($MingwBin) {
    $cache = Join-Path $Build "CMakeCache.txt"
    if (Test-Path $cache) {
        $generator = Select-String -Path $cache -Pattern "^CMAKE_GENERATOR:INTERNAL=" |
            Select-Object -First 1
        if ($generator -and $generator.Line -notmatch "MinGW Makefiles") {
            Remove-Item -Recurse -Force $Build
        }
    }
    $ConfigureArgs += @(
        "-G", "MinGW Makefiles",
        "-DCMAKE_C_COMPILER=$(Join-Path $MingwBin 'gcc.exe')",
        "-DCMAKE_CXX_COMPILER=$(Join-Path $MingwBin 'g++.exe')"
    )
}

& $QtCMakePath @ConfigureArgs
& $CMakePath --build $Build --config Release --parallel

$Executable = Join-Path $Build "Release\pomodoro-windows.exe"
if (-not (Test-Path $Executable)) {
    $Executable = Join-Path $Build "pomodoro-windows.exe"
}
if (-not (Test-Path $Executable)) {
    throw "The Windows executable was not produced."
}

$Windeployqt = Join-Path $QtBin "windeployqt.exe"
if (-not (Test-Path $Windeployqt)) {
    throw "windeployqt.exe was not found beside the Qt kit."
}
New-Item -ItemType Directory -Force -Path $Dist | Out-Null
# Keep the build copy runnable for debugging, and deploy a complete portable
# copy into dist for normal use.
& $Windeployqt --release --qmldir (Join-Path $Root "qml") --no-translations $Executable
& $Windeployqt --release --qmldir (Join-Path $Root "qml") --no-translations --dir $Dist $Executable
$DistExecutable = Join-Path $Dist "pomodoro-windows.exe"
if (-not (Test-Path $DistExecutable)) {
    Copy-Item $Executable $DistExecutable -Force
}
$Scripts = Join-Path $Build "scripts"
if (Test-Path $Scripts) {
    Copy-Item $Scripts (Join-Path $Dist "scripts") -Recurse -Force
}

Write-Host "Built: $Executable"
Write-Host "Run:   $Dist\pomodoro-windows.exe"
