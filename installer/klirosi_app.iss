; Inno Setup script for "Κλήρωση Λαχείων" (klirosi_app)
; Builds a normal Windows installer: Start Menu shortcut, optional Desktop
; shortcut, and a proper uninstaller listed in "Add or Remove Programs".
; No admin rights required -- installs to the current user's own folder.

#define MyAppName "Kliro" + "si Laxeion"
#define MyAppExeName "klirosi_app.exe"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "VIR"
#define ReleaseDir "..\build\windows\x64\runner\Release"
#define IconFile "..\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{5774084A-8E75-45A6-A235-C4FBD78CD78D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=.\output
OutputBaseFilename=KlirosiApp-Setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
