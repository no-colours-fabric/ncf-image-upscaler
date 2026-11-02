#ifndef Payload
  #error Pass /DPayload=<offline staged app>
#endif
#ifndef ArtifactRoot
  #error Pass /DArtifactRoot=<output directory>
#endif
[Setup]
AppId={{9E930EC1-F26D-4D70-A5F3-18F7C2D22360}
AppName=NCF Image Upscaler
AppVersion=0.1.0
AppVerName=NCF Image Upscaler for Windows 0.1.0
AppPublisher=no-colours-fabric
AppPublisherURL=https://github.com/no-colours-fabric/ncf-image-upscaler
DefaultDirName={localappdata}\Programs\NCF Image Upscaler
DefaultGroupName=NCF Image Upscaler
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
OutputDir={#ArtifactRoot}
OutputBaseFilename=NCFImageUpscaler-0.1.0-windows-x64-setup
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
Source: "{#Payload}\resources\NativePrerequisiteCheck.exe"; Flags: dontcopy
Source: "{#Payload}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\NCF Image Upscaler"; Filename: "{app}\NCF Image Upscaler.exe"
Name: "{autodesktop}\NCF Image Upscaler"; Filename: "{app}\NCF Image Upscaler.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\NCF Image Upscaler.exe"; Description: "Open NCF Image Upscaler"; Flags: nowait postinstall skipifsilent

[Code]
function InitializeSetup(): Boolean;
var Release: Cardinal;
    Code: Integer;
    ErrorText: String;
begin
  Result := False;
  if not (RegQueryDWordValue(HKLM64, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) and (Release >= 528040)) then begin
    SuppressibleMsgBox('This application requires Microsoft .NET Framework 4.8. Install it from Microsoft, then run this installer again. Installing a missing system prerequisite may require administrator permission. No Python installation is needed.', mbError, MB_OK, IDOK);
    exit;
  end;
  ExtractTemporaryFile('NativePrerequisiteCheck.exe');
  if not Exec(ExpandConstant('{tmp}\NativePrerequisiteCheck.exe'), '', '', SW_HIDE, ewWaitUntilTerminated, Code) then Code := 12;
  if Code <> 0 then begin
    ErrorText := 'Microsoft Visual C++ 2015-2022 Redistributable (x64), version 14.29 or newer, is required. Install or repair it from Microsoft, then run setup again. Installing a missing system prerequisite may require administrator permission. The app itself is per-user.';
    if SuppressibleMsgBox(ErrorText + #13#10 + #13#10 + 'Open the official Microsoft download page?', mbError, MB_YESNO, IDNO) = IDYES then
      ShellExec('open', 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist', '', '', SW_SHOWNORMAL, ewNoWait, Code);
    exit;
  end;
  Result := True;
end;

// No [UninstallDelete]: models, preferences, sessions and all user images stay.
