[CmdletBinding()]
param([Parameter(Mandatory)][string]$Installer)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$validationBase = Join-Path $projectRoot 'build/installer-lifecycle'
$root = Join-Path $validationBase ([guid]::NewGuid().ToString('N'))
$profile = Join-Path $root 'profile'
$program = Join-Path $root '自定义安装位置\Good Day'
$appFolder = Join-Path $program 'App'
$data = Join-Path $program 'MD'
$moved = Join-Path $root '迁移后的数据'
$config = Join-Path $profile 'AppData/Roaming/Good Day/vault-location.json'
$realConfig = Join-Path $env:USERPROFILE 'AppData/Roaming/Good Day/vault-location.json'
$realHash = if (Test-Path -LiteralPath $realConfig) { (Get-FileHash -LiteralPath $realConfig).Hash } else { $null }
$validationKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{B8DC52A7-F640-4FAE-9A0A-06487AB02389}_is1'
$startupKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$previousStartup = (Get-ItemProperty -LiteralPath $startupKey -ErrorAction SilentlyContinue).'Good Day Validation'
if (Test-Path -LiteralPath $validationKey) { throw 'A previous validation installation still exists; do not overwrite it.' }
New-Item -ItemType Directory -Path $root,$profile,(Join-Path $profile 'AppData/Roaming'),(Join-Path $profile 'AppData/Local') -Force | Out-Null
function Invoke-ValidationProcess([string]$Exe, [string[]]$Arguments) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = [IO.Path]::GetFullPath($Exe)
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.Environment['USERPROFILE'] = $profile
    $start.Environment['APPDATA'] = Join-Path $profile 'AppData/Roaming'
    $start.Environment['LOCALAPPDATA'] = Join-Path $profile 'AppData/Local'
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    if (-not $process.WaitForExit(60000)) { throw 'Validation process timed out.' }
    return $process.ExitCode
}
function Install-Validation([string[]]$Extra) {
    Invoke-ValidationProcess $Installer (@('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART','/SP-',('/TESTINSTALLDIR=' + (Join-Path $root 'fallback-must-not-be-used'))) + $Extra)
}
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
$uninstalled = $false
try {
    $firstExit = Install-Validation @(('/DIR=' + (Split-Path $program -Parent)), ('/LOG=' + (Join-Path $root 'first.log')))
    Check ($firstExit -eq 0) "First install failed: $firstExit."
    Check (Test-Path -LiteralPath (Join-Path $appFolder 'good_day.exe')) 'Custom program directory was not used.'
    $validationShell = New-Object -ComObject WScript.Shell
    $desktopLink = $validationShell.CreateShortcut((Join-Path $profile 'Desktop/Good Day Validation.lnk'))
    Check ($desktopLink.TargetPath -eq (Join-Path $appFolder 'good_day.exe')) 'Shortcut target differs.'
    Check ($desktopLink.WorkingDirectory -eq $appFolder) 'Shortcut did not use App as its working directory.'
    Check ((Get-Content -LiteralPath $config -Raw | ConvertFrom-Json).vaultPath -eq $data) 'Custom Unicode data directory was not saved.'
    $record = Join-Path $data 'keep.md'
    [IO.File]::WriteAllText($record, '# Keep this Markdown record', [Text.UTF8Encoding]::new($false))
    $recordHash = (Get-FileHash -LiteralPath $record).Hash
    $configHash = (Get-FileHash -LiteralPath $config).Hash
    # Simulate the former runtime layout and protect arbitrary user Markdown.
    Copy-Item -LiteralPath (Join-Path $appFolder 'good_day.exe') -Destination (Join-Path $program 'good_day.exe')
    Copy-Item -LiteralPath (Join-Path $appFolder 'flutter_windows.dll') -Destination (Join-Path $program 'flutter_windows.dll')
    New-Item -ItemType Directory -Path (Join-Path $program 'data') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $program 'data/keep-user.md'), '# User file outside managed runtime', [Text.UTF8Encoding]::new($false))
    New-ItemProperty -LiteralPath $startupKey -Name 'Good Day Validation' -Value ('"' + (Join-Path $program 'good_day.exe') + '"') -PropertyType String -Force | Out-Null
    Check ((Install-Validation @('/DATADIR=' + (Join-Path $root 'ignored-data'), '/LOG=' + (Join-Path $root 'upgrade.log'))) -eq 0) 'Upgrade failed.'
    Check ((Get-ItemProperty -LiteralPath $validationKey).InstallLocation.TrimEnd('\') -eq $program) 'Previous program location was not detected.'
    Check ((Get-FileHash -LiteralPath $config).Hash -eq $configHash) 'Upgrade rewrote the existing data location.'
    Check ((Get-FileHash -LiteralPath $record).Hash -eq $recordHash) 'Upgrade changed Markdown data.'
    Check (-not (Test-Path -LiteralPath (Join-Path $root 'ignored-data'))) 'Upgrade used the requested wrong data directory.'
    Check (-not (Test-Path -LiteralPath (Join-Path $program 'good_day.exe'))) 'Old executable was left behind.'
    Check (-not (Test-Path -LiteralPath (Join-Path $program 'flutter_windows.dll'))) 'Old runtime was left behind.'
    Check ([IO.File]::ReadAllText((Join-Path $program 'data/keep-user.md')) -eq '# User file outside managed runtime') 'Legacy cleanup deleted user Markdown.'
    Check ((Get-ItemPropertyValue -LiteralPath $startupKey -Name 'Good Day Validation') -eq ('"' + (Join-Path $appFolder 'good_day.exe') + '"')) 'Startup still points to the old executable.'
    New-Item -ItemType Directory -Path $moved | Out-Null
    Copy-Item -LiteralPath $record -Destination (Join-Path $moved 'keep.md')
    [IO.File]::WriteAllText($config, (@{vaultPath=$moved} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $movedConfigHash = (Get-FileHash -LiteralPath $config).Hash
    Check ((Install-Validation @('/LOG=' + (Join-Path $root 'moved-upgrade.log'))) -eq 0) 'Upgrade after changing the data directory failed.'
    Check ((Get-FileHash -LiteralPath $config).Hash -eq $movedConfigHash) 'Migrated location was overwritten.'
    Check ((Get-FileHash -LiteralPath (Join-Path $moved 'keep.md')).Hash -eq $recordHash) 'Migrated Markdown changed.'
    # Isolated application-driven upgrade: wait for caller, install, reopen.
    $waiter = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-NonInteractive','-Command','Start-Sleep -Seconds 5') -WindowStyle Hidden -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    Check ((Install-Validation @('/GOODDAYUPDATE=1', ('/GOODDAYWAITPID=' + $waiter.Id), ('/LOG=' + (Join-Path $root 'in-app-update.log')))) -eq 0) 'In-app upgrade failed.'
    $watch.Stop()
    Check ($watch.Elapsed.TotalSeconds -ge 4) 'Installer did not wait for the caller to exit.'
    $reopened = @()
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        $reopened = @(Get-Process good_day -ErrorAction SilentlyContinue | Where-Object Path -EQ (Join-Path $appFolder 'good_day.exe'))
        if ($reopened.Count) { break }
        Start-Sleep -Milliseconds 200
    }
    Check ($reopened.Count -eq 1) 'In-app update did not reopen the app.'
    Start-Sleep -Seconds 2
    foreach ($testApp in $reopened) { Stop-Process -Id $testApp.Id; Wait-Process -Id $testApp.Id -Timeout 15 -ErrorAction SilentlyContinue }
    Check ((Get-FileHash -LiteralPath $config).Hash -eq $movedConfigHash) 'In-app update changed the data location.'
    Check ((Get-FileHash -LiteralPath (Join-Path $moved 'keep.md')).Hash -eq $recordHash) 'In-app update changed Markdown.'
    [long]$hash = 0
    foreach ($character in ([IO.Path]::GetFullPath((Join-Path $appFolder 'good_day.exe')).ToLowerInvariant()).ToCharArray()) { $hash = ($hash * 31 + [int]$character) % 1000000007 }
    $mutex = [Threading.Mutex]::new($false, ('Local\GoodDay.Setup.' + $hash))
    try {
        Check ((Install-Validation @('/LOG=' + (Join-Path $root 'running-block.log'))) -ne 0) 'Running application was not protected.'
        Check ((Get-FileHash -LiteralPath $config).Hash -eq $movedConfigHash) 'Blocked upgrade changed configuration.'
    } finally { $mutex.Dispose() }
    $validConfig = [IO.File]::ReadAllBytes($config)
    [IO.File]::WriteAllText($config, 'invalid original configuration', [Text.UTF8Encoding]::new($false))
    Check ((Install-Validation @('/LOG=' + (Join-Path $root 'invalid-block.log'))) -ne 0) 'Invalid configuration was overwritten.'
    Check ([IO.File]::ReadAllText($config) -eq 'invalid original configuration') 'Invalid original configuration was lost.'
    [IO.File]::WriteAllBytes($config, $validConfig)
    Check ((Invoke-ValidationProcess (Join-Path $program 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART')) -eq 0) 'Uninstall failed.'
    $uninstalled = $true
    Check ((Get-FileHash -LiteralPath (Join-Path $moved 'keep.md')).Hash -eq $recordHash) 'Uninstall removed data.'
    Check ((Get-FileHash -LiteralPath $config).Hash -eq $movedConfigHash) 'Uninstall removed location settings.'
    Check (-not (Test-Path -LiteralPath $validationKey)) 'Uninstall left its registration behind.'
    if ($realHash) { Check ((Get-FileHash -LiteralPath $realConfig).Hash -eq $realHash) 'Personal configuration was touched.' }
    $receipt = [pscustomobject]@{ FirstInstall=$true; SingleRootWithAppAndMd=$true; LocaleIndependentFolderName=$true; LegacyRuntimeCleaned=$true; LegacyUserMarkdownKept=$true; StartupLocationUpdated=$true; UpgradeKeepsLocationsAndMarkdown=$true; MigratedLocationDetected=$true; RunningAppProtected=$true; InvalidConfigProtected=$true; UninstallKeepsData=$true; PersonalConfigUnchanged=$true }
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $validationBase 'receipt.json') -Encoding utf8
    $receipt | ConvertTo-Json
} finally {
    if ($null -ne $previousStartup) { New-ItemProperty -LiteralPath $startupKey -Name 'Good Day Validation' -Value $previousStartup -PropertyType String -Force | Out-Null }
    else { Remove-ItemProperty -LiteralPath $startupKey -Name 'Good Day Validation' -ErrorAction SilentlyContinue }
    $logs = Join-Path $validationBase 'latest-logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    Get-ChildItem -LiteralPath $root -Filter '*.log' | Copy-Item -Destination $logs -Force
    if (-not $uninstalled -and (Test-Path -LiteralPath (Join-Path $program 'unins000.exe'))) { Invoke-ValidationProcess (Join-Path $program 'unins000.exe') @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART') | Out-Null }
    $resolved = [IO.Path]::GetFullPath($root)
    $prefix = [IO.Path]::GetFullPath($validationBase) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe validation cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
