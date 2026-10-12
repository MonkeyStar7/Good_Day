#ifndef AppVersion
  #define AppVersion "1.4.4"
#endif
#ifndef AppBuild
  #define AppBuild "18"
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
DefaultGroupName={#SetupName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#ReleaseDir}
OutputBaseFilename=Good-Day-{#AppVersion}-windows-x64-setup
SetupIconFile={#BundleDir}\app_icon.ico
UninstallDisplayIcon={app}\good_day.exe
VersionInfoVersion={#AppVersion}.{#AppBuild}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "chinesesimplified"; MessagesFile: "ChineseSimplified.isl"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#SetupName}"; Filename: "{app}\good_day.exe"
Name: "{userdesktop}\{#SetupName}"; Filename: "{app}\good_day.exe"

[Run]
Filename: "{app}\good_day.exe"; Description: "打开 Good Day"; Flags: nowait postinstall skipifsilent

[Code]
var
  DataPage: TInputDirWizardPage;
  ConfigFile, ExistingData: String;

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
  DataPage := CreateInputDirPage(wpSelectDir, 'Markdown 数据位置',
    '选择待办数据保存在哪里',
    '程序与数据分开保存。升级和卸载不会删除此目录中的待办记录。', False, 'Good Day Vault');
  DataPage.Add('数据文件夹：');
  if ExistingData <> '' then begin
    DataPage.Values[0] := ExistingData;
    DataPage.Edits[0].ReadOnly := True;
    DataPage.Buttons[0].Enabled := False;
    DataPage.SubCaptionLabel.Caption := '已检测到现有数据，升级将沿用此位置。需要迁移时，请在软件设置中更改数据目录。';
  end else DataPage.Values[0] := ExpandConstant('{param:DATADIR|{userdocs}\Good Day Vault}');
end;

function SetupMutexName(const Path: String): String;
var I: Integer; Hash: Int64; Normalized: String;
begin
  Normalized := Lowercase(Path);
  Hash := 0;
  for I := 1 to Length(Normalized) do Hash := (Hash * 31 + Ord(Normalized[I])) mod 1000000007;
  Result := 'Local\GoodDay.Setup.' + IntToStr(Hash);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var Data, App, Probe: String;
begin
  Result := '';
  if CheckForMutexes(SetupMutexName(ExpandConstant('{app}\good_day.exe'))) then begin
    Result := '请先在任务栏托盘中右键 Good Day，选择“退出”，保存待办后再重试安装。';
    Exit;
  end;
  if FileExists(ConfigFile) and (ExistingData = '') then begin
    Result := '现有数据目录设置无法读取。请先打开 Good Day 修复数据位置，再运行安装包。';
    Exit;
  end;
  Data := AddBackslash(Lowercase(ExpandFileName(DataPage.Values[0])));
  App := AddBackslash(Lowercase(ExpandConstant('{app}')));
  if (Pos(App, Data) = 1) or (Pos(Data, App) = 1) then begin
    Result := '请将数据放在程序目录以外的独立文件夹。'; Exit;
  end;
  if not ForceDirectories(DataPage.Values[0]) then begin Result := '无法创建数据文件夹，请选择可写入的位置。'; Exit; end;
  Probe := AddBackslash(DataPage.Values[0]) + '.goodday-installer-' + IntToStr(GetTickCount) + '.tmp';
  if FileExists(Probe) then begin Result := '临时检查文件已存在，请重新运行安装。'; Exit; end;
  if not SaveStringToFile(Probe, 'Good Day', False) then Result := '无法写入数据文件夹，请检查权限或磁盘连接。'
  else DeleteFile(Probe);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Parameters: String;
begin
  if CurStep = ssPostInstall then begin
    Parameters := '--setup-vault="' + DataPage.Values[0] + '"';
#ifdef InstallerValidation
    Parameters := Parameters + ' --setup-config="' + ExtractFileDir(ConfigFile) + '"';
#endif
    if not Exec(ExpandConstant('{app}\good_day.exe'), Parameters,
      ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, Code) then
      RaiseException('无法保存数据位置。现有待办未被改动。');
    if (Code <> 0) or (CompareText(ReadVaultPath(ConfigFile), DataPage.Values[0]) <> 0) then
      RaiseException('数据位置未保存，请检查目录权限。现有待办未被改动。');
  end;
end;
