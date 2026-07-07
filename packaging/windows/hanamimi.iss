; Hanamimi+ -- Inno Setup installer (ARCHITECTURE-DESKTOP.md section 7).
;
; Compile:  ISCC.exe /DAppVersion=1.2.3 hanamimi.iss
; ReleaseDir defaults to the flutter build output; override with
; /DReleaseDir=... if building from elsewhere.
;
; Design: per-user install by default (no UAC; the in-app updater can
; hand off to a newer setup.exe without elevation), user picks the
; folder, Start menu entry always, desktop icon as a checked task,
; launch after install. The app self-fetches yt-dlp/ffmpeg on first
; run, but the CI build bundles them so day one works offline.
;
; ASCII-only on purpose (ANSI compiler default).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef ReleaseDir
  #define ReleaseDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{DD4AB97E-0579-47B0-ABAE-357F2836C893}
AppName=Hanamimi+
AppVersion={#AppVersion}
AppVerName=Hanamimi+ {#AppVersion}
AppPublisher=Sappy
AppPublisherURL=https://github.com/ShaptakNaskar/hanamimi
AppSupportURL=https://github.com/ShaptakNaskar/hanamimi/issues
DefaultDirName={autopf}\Hanamimi+
DefaultGroupName=Hanamimi+
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=hanamimi-plus-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\hanamimi.exe
UninstallDisplayName=Hanamimi+
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Hanamimi+"; Filename: "{app}\hanamimi.exe"
Name: "{autodesktop}\Hanamimi+"; Filename: "{app}\hanamimi.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\hanamimi.exe"; Description: "{cm:LaunchProgram,Hanamimi+}"; Flags: nowait postinstall skipifsilent
