#Requires -Version 7
<#
Publishes the WinUI app self-contained and wraps it in an Inno Setup installer.

Produces, in dist/:
  Pomodoro-<version>-windows-x64.exe        installer
  Pomodoro-<version>-windows-x64.exe.sha256
  Pomodoro-<version>-windows-x64.zip        portable, always written
  Pomodoro-<version>-windows-x64.zip.sha256

Environment:
  VERSION                     marketing version (default 0.0.0-dev)
  GOOGLE_OAUTH_CLIENT_JSON    OAuth client JSON, inline; baked into the build
  GOOGLE_OAUTH_CLIENT_FILE    ...or a path to the same JSON
#>
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot
$version = if ($env:VERSION) { $env:VERSION } else { '0.0.0-dev' }
$project = Join-Path $root 'src/Pomodoro.App/Pomodoro.App.csproj'
$publish = Join-Path $root 'src/Pomodoro.App/bin/x64/Release/net8.0-windows10.0.19041.0/win-x64/publish'
$dist = Join-Path $root 'dist'

# WindowsAppSDK's resource-index tasks ship with Visual Studio, not the .NET
# SDK, so `dotnet publish` cannot build this project.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
    -find MSBuild\**\Bin\MSBuild.exe | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild not found' }

Write-Host "==> Publishing $version"
& $msbuild $project -t:Publish -restore `
    -p:Configuration=Release -p:Platform=x64 -p:RuntimeIdentifier=win-x64 `
    -p:SelfContained=true -p:PublishSingleFile=false `
    -p:Version=$version -v:minimal
if ($LASTEXITCODE -ne 0) { throw 'publish failed' }
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

New-Item -ItemType Directory -Force -Path $dist | Out-Null
$name = "Pomodoro-$version-windows-x64"

Write-Host '==> Packaging portable zip'
$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $zip

Write-Host '==> Building installer'
$iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if (-not $iscc) {
    $candidate = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
    if (Test-Path $candidate) { $iscc = $candidate } else { $iscc = $null }
} else {
    $iscc = $iscc.Source
}
if ($iscc) {
    & $iscc (Join-Path $root 'Pomodoro.iss') `
        "/DAppVersion=$version" "/DSourceDir=$publish" "/Qp"
    if ($LASTEXITCODE -ne 0) { throw 'installer build failed' }
} else {
    Write-Warning 'Inno Setup (ISCC.exe) not found; only the portable zip was produced'
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
