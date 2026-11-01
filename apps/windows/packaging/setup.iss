#ifndef Payload
  #error Pass /DPayload=<offline staged app>
#endif
#ifndef ArtifactRoot
  #error Pass /DArtifactRoot=<output directory>
#endif
[Setup]
AppId={{9E930EC1-F26D-4D70-A5F3-18F7C2D22360}
AppName=NCF Image Upscaler
AppVersion=0.1.0-preview.1
AppVerName=NCF Image Upscaler for Windows 0.1.0 Preview 1
AppPublisher=no-colours-fabric
AppPublisherURL=https://github.com/no-colours-fabric/ncf-image-upscaler
DefaultDirName={localappdata}\Programs\NCF Image Upscaler
DefaultGroupName=NCF Image Upscaler
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir={#ArtifactRoot}
OutputBaseFilename=NCFImageUpscaler-0.1.0-preview.1-windows-x64-setup
SetupIconFile={#Payload}\resources\App.ico
UninstallDisplayIcon={app}\NCF Image Upscaler.exe
CloseApplications=yes
RestartApplications=no
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
InfoBeforeFile=installer-info.txt
Uninstallable=yes

[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NCF Image Upscaler"; Filename: "{app}\NCF Image Upscaler.exe"
Name: "{autodesktop}\NCF Image Upscaler"; Filename: "{app}\NCF Image Upscaler.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\NCF Image Upscaler.exe"; Description: "Open NCF Image Upscaler"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var Release: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) and (Release >= 528040);
  if not Result then
    MsgBox('This preview requires Microsoft .NET Framework 4.8. Install it from Microsoft, then run this installer again. No Python installation is needed.', mbError, MB_OK);
end;

// No [UninstallDelete]: models, preferences, sessions and all user images stay.
