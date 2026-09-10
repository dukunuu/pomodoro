#Requires -Version 7
<#
Publishes the WinUI app self-contained and wraps it in an Inno Setup installer.

Produces, in dist/, for each architecture:
  Pomodoro-<version>-windows-<arch>.exe     installer
  Pomodoro-<version>-windows-<arch>.zip     portable, always written
  ...and a .sha256 beside each

Environment:
  VERSION                     marketing version (default 0.0.0-dev)
  ARCHS                       comma-separated: x64, arm64 (default both)
  GOOGLE_OAUTH_CLIENT_JSON    OAuth client JSON, inline; baked into the build
  GOOGLE_OAUTH_CLIENT_FILE    ...or a path to the same JSON

Windows on ARM runs x64 under emulation, so an x64-only release works
everywhere but runs slowly on ARM devices. Both are published.
#>
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$version = if ($env:VERSION) { $env:VERSION } else { '0.0.0-dev' }
$archs = if ($env:ARCHS) { $env:ARCHS -split ',' } else { @('x64', 'arm64') }
$project = Join-Path $root 'src/Pomodoro.App/Pomodoro.App.csproj'
$dist = Join-Path $root 'dist'

# WindowsAppSDK's resource-index tasks ship with Visual Studio, not the .NET
# SDK, so `dotnet publish` cannot build this project.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
    -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild not found' }

$iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if ($iscc) {
    $iscc = $iscc.Source
} else {
    $candidate = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    $iscc = if (Test-Path $candidate) { $candidate } else { $null }
}

New-Item -ItemType Directory -Force -Path $dist | Out-Null

foreach ($arch in $archs) {
    $arch = $arch.Trim()
    $platform = if ($arch -eq 'arm64') { 'ARM64' } else { 'x64' }
    $rid = "win-$arch"
    $publish = Join-Path $root "src/Pomodoro.App/bin/$platform/Release/net8.0-windows10.0.19041.0/$rid/publish"

    Write-Host "==> Publishing $version ($arch)"
    & $msbuild $project -t:Publish -restore `
        -p:Configuration=Release -p:Platform=$platform -p:RuntimeIdentifier=$rid `
        -p:SelfContained=true -p:PublishSingleFile=false `
        -p:Version=$version -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "publish failed for $arch" }
    if (-not (Test-Path (Join-Path $publish 'Pomodoro.exe'))) {
        throw "Pomodoro.exe not found in $publish"
    }

    # Bake in the OAuth client when one is supplied, so a release can be
    # authorized without every user creating their own Google Cloud project.
    $clientDest = Join-Path $publish 'google-calendar-client.json'
    if ($env:GOOGLE_OAUTH_CLIENT_JSON) {
        [IO.File]::WriteAllText($clientDest, $env:GOOGLE_OAUTH_CLIENT_JSON)
    } elseif ($env:GOOGLE_OAUTH_CLIENT_FILE) {
        Copy-Item $env:GOOGLE_OAUTH_CLIENT_FILE $clientDest -Force
    }
    if (Test-Path $clientDest) {
        $client = Get-Content $clientDest -Raw | ConvertFrom-Json
        $section = if ($client.installed) { $client.installed } else { $client.web }
        if (-not $section -or -not $section.client_id) {
            throw 'supplied OAuth client JSON is not a valid Desktop client'
        }
        Write-Host '    baked in OAuth client'
    } else {
        Write-Host '    no OAuth client supplied; users install their own in Settings'
    }

    $name = "Pomodoro-$version-windows-$arch"

    Write-Host "==> Packaging portable zip ($arch)"
    $zip = Join-Path $dist "$name.zip"
    if (Test-Path $zip) { Remove-Item $zip }
    Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip

    if ($iscc) {
        Write-Host "==> Building installer ($arch)"
        & $iscc (Join-Path $root 'Pomodoro.iss') `
            "/DAppVersion=$version" "/DSourceDir=$publish" "/DArch=$arch"
        if ($LASTEXITCODE -ne 0) { throw "installer build failed for $arch" }
    } else {
        Write-Warning 'Inno Setup (ISCC.exe) not found; only the portable zip was produced'
    }
}

# -Include without -Recurse or a wildcard path matches nothing, which
# silently produced no checksums at all.
Get-ChildItem -Path $dist -File |
    Where-Object { $_.Extension -in '.exe', '.zip' } |
    ForEach-Object {
    $hash = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    "$hash  $($_.Name)" | Set-Content "$($_.FullName).sha256"
    Write-Host "    $($_.Name)  $([math]::Round($_.Length / 1MB, 1)) MB"
}
Write-Host "Artifacts in $dist"
