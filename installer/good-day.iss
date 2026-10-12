#ifndef AppVersion
  #define AppVersion "1.4.8"
#endif
#ifndef AppBuild
  #define AppBuild "22"
#endif
#ifndef BundleDir
  #error BundleDir is required
#endif
#ifndef ReleaseDir
  #error ReleaseDir is required
#endif
#ifndef SetupId
  #define SetupId "C5014FDB-E3BB-4CDF-A77E-3DE8FB1632A0"
#endif
#ifndef SetupName
  #define SetupName "Good Day"
#endif

[Setup]
AppId={{{#SetupId}}
AppName={#SetupName}
AppVersion={#AppVersion}
AppVerName={#SetupName} {#AppVersion}
AppPublisher=MonkeyStar7
AppPublisherURL=https://github.com/MonkeyStar7/Good_Day
#ifdef InstallerValidation
DefaultDirName={param:TESTINSTALLDIR|{localappdata}\Programs\Good Day Validation}
#else
DefaultDirName={localappdata}\Programs\Good Day
#endif
UsePreviousAppDir=yes
DisableDirPage=no
AppendDefaultDirName=yes
DefaultGroupName={#SetupName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#ReleaseDir}
OutputBaseFilename=Good-Day-{#AppVersion}-windows-x64-setup
SetupIconFile={#BundleDir}\app_icon.ico
UninstallDisplayIcon={app}\App\good_day.exe
VersionInfoVersion={#AppVersion}.{#AppBuild}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[InstallDelete]
#include "legacy-runtime.iss"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}\App"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#SetupName}"; Filename: "{app}\App\good_day.exe"; WorkingDir: "{app}\App"
Name: "{userdesktop}\{#SetupName}"; Filename: "{app}\App\good_day.exe"; WorkingDir: "{app}\App"

[Run]
Filename: "{app}\App\good_day.exe"; WorkingDir: "{app}\App"; Description: "打开 Good Day"; Flags: nowait postinstall skipifsilent

[Code]
var
  ConfigFile, ExistingData, RegisteredRoot: String;
  LegacyLayout: Boolean;

function GetTickCount: LongWord;
  external 'GetTickCount@kernel32.dll stdcall';

function ConfigPath: String;
var Profile: String;
begin
  Profile := GetEnv('USERPROFILE');
  if Profile = '' then Result := ExpandConstant('{userappdata}\Good Day\vault-location.json')
  else Result := Profile + '\AppData\Roaming\Good Day\vault-location.json';
end;

{ Read the JSON string without rewriting an existing location file. }
function ReadVaultPath(const FileName: String): String;
var Source: AnsiString; Text: String; I, Code: Integer; C: Char;
begin
  Result := '';
  if not LoadStringFromFile(FileName, Source) then Exit;
  Text := UTF8Decode(Source);
  I := Pos('"vaultPath"', Text);
  if I = 0 then Exit;
  I := I + Length('"vaultPath"');
  while (I <= Length(Text)) and (Text[I] <> ':') do I := I + 1;
  I := I + 1;
  while (I <= Length(Text)) and (Text[I] <= ' ') do I := I + 1;
  if (I > Length(Text)) or (Text[I] <> '"') then Exit;
  I := I + 1;
  while I <= Length(Text) do begin
    C := Text[I];
    if C = '"' then Exit;
    if C = '\' then begin
      I := I + 1;
      if I > Length(Text) then begin Result := ''; Exit; end;
      C := Text[I];
      if C = 'u' then begin
        if I + 4 > Length(Text) then begin Result := ''; Exit; end;
        Code := StrToIntDef('$' + Copy(Text, I + 1, 4), -1);
        if Code < 0 then begin Result := ''; Exit; end;
        C := Chr(Code);
        I := I + 4;
      end else if (C <> '\') and (C <> '/') and (C <> '"') then begin Result := ''; Exit; end;
    end;
    Result := Result + C;
    I := I + 1;
  end;
  Result := '';
end;

procedure InitializeWizard;
begin
  ConfigFile := ConfigPath;
  ExistingData := ReadVaultPath(ConfigFile);
#ifndef InstallerValidation
  if ExistingData = '' then
    ExistingData := ReadVaultPath(GetEnv('USERPROFILE') + '\AppData\Roaming\com.goodday\Good Day\Good Day\vault-location.json');
#endif
  RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\' + '{' + '{#SetupId}' + '}_is1', 'InstallLocation', RegisteredRoot);
  WizardForm.SelectDirLabel.Caption := '只需选择一次 Good Day 主文件夹。程序放在 App，首次安装的数据放在 MD。升级沿用现有数据位置。';

end;

function SetupMutexName(const Path: String): String;
var I: Integer; Hash: Int64; Normalized: String;
begin
  Normalized := Lowercase(Path);
  Hash := 0;
  for I := 1 to Length(Normalized) do Hash := (Hash * 31 + Ord(Normalized[I])) mod 1000000007;
  Result := 'Local\GoodDay.Setup.' + IntToStr(Hash);
end;

function DataDirectory: String;
begin
  if ExistingData <> '' then Result := ExistingData
  else Result := AddBackslash(ExpandConstant('{app}')) + 'MD';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var Root: String;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    Root := RemoveBackslashUnlessRoot(ExpandFileName(WizardDirValue));
    if CompareText(ExtractFileName(Root), 'Good Day') <> 0 then Root := AddBackslash(Root) + 'Good Day';
    WizardForm.DirEdit.Text := Root;
  end;
end;

function IsLegacyProgram: Boolean;
begin
  Result := LegacyLayout;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Data, App, Probe, CurrentData: String;
begin
  Result := '';
  if CheckForMutexes(SetupMutexName(ExpandConstant('{app}\App\good_day.exe'))) or CheckForMutexes(SetupMutexName(ExpandConstant('{app}\good_day.exe'))) then begin
    Result := '请先在任务栏托盘中右键 Good Day，选择“退出”，保存待办后再重试安装。';
    Exit;
  end;
  CurrentData := ReadVaultPath(ConfigFile);
  if CurrentData <> '' then ExistingData := CurrentData;
  if FileExists(ConfigFile) and (CurrentData = '') then begin
    Result := '现有数据目录设置无法读取。请先打开 Good Day 修复数据位置，再运行安装包。';
    Exit;
  end;
  Data := AddBackslash(Lowercase(ExpandFileName(DataDirectory)));
  App := AddBackslash(Lowercase(ExpandConstant('{app}\App')));
  if (Pos(App, Data) = 1) or (Pos(Data, App) = 1) then begin
    Result := '数据不能放在 App 程序目录中，请先在软件设置中迁移。'; Exit;
  end;
  if not ForceDirectories(DataDirectory) then begin Result := '无法创建数据文件夹，请选择可写入的位置。'; Exit; end;
  LegacyLayout := (RegisteredRoot <> '') and (CompareText(RemoveBackslashUnlessRoot(RegisteredRoot), ExpandConstant('{app}')) = 0) and FileExists(ExpandConstant('{app}\good_day.exe')) and FileExists(ExpandConstant('{app}\flutter_windows.dll'));
  Probe := AddBackslash(DataDirectory) + '.goodday-installer-' + IntToStr(GetTickCount) + '.tmp';
  if FileExists(Probe) then begin Result := '临时检查文件已存在，请重新运行安装。'; Exit; end;
  if not SaveStringToFile(Probe, 'Good Day', False) then Result := '无法写入数据文件夹，请检查权限或磁盘连接。'
  else DeleteFile(Probe);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Parameters, StartupCommand: String;
begin
  if CurStep = ssPostInstall then begin
    Parameters := '--setup-vault="' + DataDirectory + '"';
#ifdef InstallerValidation
    Parameters := Parameters + ' --setup-config="' + ExtractFileDir(ConfigFile) + '"';
#endif
    if not Exec(ExpandConstant('{app}\App\good_day.exe'), Parameters,
      ExpandConstant('{app}\App'), SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('无法保存数据位置。现有待办未被改动。');
    if (Code <> 0) or (CompareText(ReadVaultPath(ConfigFile), DataDirectory) <> 0) then
      RaiseException('数据位置未保存，请检查目录权限。现有待办未被改动。');
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#SetupName}', StartupCommand) then begin
      if (RegisteredRoot <> '') and (Pos(Lowercase(AddBackslash(RegisteredRoot) + 'good_day.exe'), Lowercase(StartupCommand)) > 0) then
        RegWriteStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{#SetupName}', '"' + ExpandConstant('{app}\App\good_day.exe') + '"');
    end;
  end;
end;
