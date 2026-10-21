; Windows x64 安装向导：版本、暂存目录、输出目录由 build.ps1 传入。
#ifndef SourceDir
  #error SourceDir must be provided by windows/packaging/build.ps1
#endif

[Setup]
; 固定应用标识用于原目录升级及统一卸载入口，发布新版本时不得更换。
AppId={{FA4D3950-4822-4AD7-BE0D-2A76C46C2AFE}
AppName=Remlark
AppVersion={#AppVersion}
VersionInfoVersion={#ResourceVersion}
AppPublisher=Remlark
DefaultDirName={localappdata}\Programs\Remlark
DefaultGroupName=Remlark
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
#if InstallerArch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0
OutputDir={#DistDir}
OutputBaseFilename={#InstallerName}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\remlark.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "languages\LICENSE"; DestDir: "{app}\licenses"; DestName: "inno-chinese-translation.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Remlark"; Filename: "{app}\remlark.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Remlark"; Filename: "{app}\remlark.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\remlark.exe"; Description: "{cm:LaunchProgram,Remlark}"; Flags: nowait postinstall skipifsilent

; 仅卸载安装器管理的程序文件，用户数据库、凭据、日志不在安装目录内，不做额外删除。
