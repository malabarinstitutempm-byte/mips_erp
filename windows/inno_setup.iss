[Setup]
AppName=MIPS ERP
AppVersion=2.0.0
DefaultDirName={autopf}\MIPS ERP
DefaultGroupName=MIPS ERP
UninstallDisplayIcon={app}\mips_erp.exe
Compression=lzma2
SolidCompression=yes
OutputDir=..\build\installer
OutputBaseFilename=MIPS_ERP_Installer

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MIPS ERP"; Filename: "{app}\mips_erp.exe"
Name: "{autodesktop}\MIPS ERP"; Filename: "{app}\mips_erp.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\mips_erp.exe"; Description: "Launch MIPS ERP"; Flags: nowait postinstall skipifsilent
