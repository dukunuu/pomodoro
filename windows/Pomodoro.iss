; Inno Setup script for the unpackaged, self-contained WinUI build.
; Invoked by build-windows.ps1, which passes AppVersion and SourceDir.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "src\Pomodoro.App\bin\x64\Release\net8.0-windows10.0.19041.0\win-x64\publish"
#endif
#ifndef Arch
  #define Arch "x64"
#endif

[Setup]
AppId={{7C3F2A64-9E1B-4D5A-9C77-2F1B6E4A8D31}
AppName=Pomodoro
AppVersion={#AppVersion}
AppPublisher=dukunuu
DefaultDirName={autopf}\Pomodoro
DefaultGroupName=Pomodoro
DisableProgramGroupPage=yes
; Per-user install needs no elevation, which keeps SmartScreen friction lower
; for an unsigned build.
PrivilegesRequiredOverridesAllowed=dialog
PrivilegesRequired=lowest
OutputDir=dist
OutputBaseFilename=Pomodoro-{#AppVersion}-windows-{#Arch}
SetupIconFile=src\Pomodoro.App\Assets\pomodoro.ico
; Deliberately not lzma2/max with solid compression: that needs a large
; dictionary to decompress, and when the allocation fails on a memory-limited
; machine Inno reports it as "the setup files are corrupted". A slightly
; larger installer is worth an install that works everywhere.
Compression=lzma2/normal
SolidCompression=no
WizardStyle=modern
; An ARM64 build must refuse to install on x64; an x64 build is allowed on
; ARM64, where Windows runs it under emulation.
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
UninstallDisplayIcon={app}\Pomodoro.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked
Name: "startup"; Description: "Start Pomodoro when I sign in"; GroupDescription: "Startup:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Pomodoro"; Filename: "{app}\Pomodoro.exe"
Name: "{group}\Uninstall Pomodoro"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Pomodoro"; Filename: "{app}\Pomodoro.exe"; Tasks: desktopicon
Name: "{userstartup}\Pomodoro"; Filename: "{app}\Pomodoro.exe"; Tasks: startup

[Run]
Filename: "{app}\Pomodoro.exe"; Description: "Launch Pomodoro"; Flags: nowait postinstall skipifsilent
; An in-app update installs silently, which skips the entry above, so the app
; would never come back. Relaunch it explicitly in that case.
Filename: "{app}\Pomodoro.exe"; Flags: nowait; Check: WizardSilent
