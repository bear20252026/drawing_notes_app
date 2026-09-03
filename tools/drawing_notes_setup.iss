; 绘图笔记 (drawing_notes_app) Windows 安装包脚本
; Inno Setup 6 编译 => setup_绘图笔记_<版本>.exe
; 说明：本脚本位于 tools/，路径均相对本脚本所在目录，可在仓库内直接复现打包。

#define MyAppName "绘图笔记"
#define MyAppVersion "1.9.2"
#define MyAppPublisher "Drawing Notes Studio"
#define MyAppExeName "drawing_notes_app.exe"
; Release 构建产物（相对 tools/）
#define MyRelease "..\build\windows\x64\runner\Release"

[Setup]
; AppId 是安装包唯一标识，勿随意更改，否则视为不同 App 无法升级覆盖
AppId={{135D94E4-6BE7-4292-ABF0-3EC239D96A45}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion=1.1.0
AppPublisher={#MyAppPublisher}
AppPublisherURL=https://github.com/bear20252026/drawing_notes_app
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
; 安装包输出目录（相对 tools/，落在 build/ 下不入仓）
OutputDir=..\build\windows\installer
OutputBaseFilename=setup_drawing_notes_{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64os
PrivilegesRequired=admin
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#MyRelease}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
