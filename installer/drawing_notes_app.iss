; Inno Setup 脚本——drawing_notes_app Windows 安装包（2026-08-22）
; 含全部 8 项加密加强——打包 release exe + data 资源 + DLLs
; 注意：路径相对本 .iss 所在目录（installer/——加 ..\ 前缀）

[Setup]
AppName=绘图笔记
AppVersion=1.1.0.2
AppPublisher=DrawingNotes
DefaultDirName={autopf}\DrawingNotes
DefaultGroupName=绘图笔记
OutputDir=..\dist\1.1.0+2
OutputBaseFilename=drawing_notes_app-1.1.0+2-windows-setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
WizardStyle=modern

[Files]
Source: "..\build\windows\x64\runner\Release\drawing_notes_app.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\dartjni.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\file_selector_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\hotkey_manager_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\pdfx_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\绘图笔记"; Filename: "{app}\drawing_notes_app.exe"
Name: "{autodesktop}\绘图笔记"; Filename: "{app}\drawing_notes_app.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务:"

[Run]
Filename: "{app}\drawing_notes_app.exe"; Description: "运行绘图笔记"; Flags: nowait postinstall skipifsilent
