[CmdletBinding()]
param([string]$Compiler = 'ISCC.exe', [switch]$Validation)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$versionMatch = Select-String -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') -Pattern '^version:\s*([0-9.]+)\+([0-9]+)'
$version = $versionMatch.Matches[0].Groups[1].Value
$build = $versionMatch.Matches[0].Groups[2].Value
$releaseRoot = Join-Path $projectRoot 'build/releases'
$archive = Join-Path $releaseRoot "Good-Day-$version-windows-x64.zip"
$stage = Join-Path $releaseRoot ('installer-stage-' + [guid]::NewGuid().ToString('N'))
$output = if ($Validation) { Join-Path $releaseRoot 'installer-validation' } else { $releaseRoot }
New-Item -ItemType Directory -Path $stage,$output -Force | Out-Null
try {
    Expand-Archive -LiteralPath $archive -DestinationPath $stage
    $bundle = Join-Path $stage 'Good Day'
    $arguments = @("/DAppVersion=$version", "/DAppBuild=$build", "/DBundleDir=$bundle", "/DReleaseDir=$output")
    if ($Validation) { $arguments += @('/DSetupId=B8DC52A7-F640-4FAE-9A0A-06487AB02389', '/DSetupName=Good Day Validation', '/DInstallerValidation=1') }
    & $Compiler @arguments (Join-Path $projectRoot 'installer/good-day.iss')
    if ($LASTEXITCODE -ne 0) { throw 'Installer compilation failed.' }
    $setup = Join-Path $output "Good-Day-$version-windows-x64-setup.exe"
    $hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $setup -Leaf)" | Set-Content -LiteralPath "$setup.sha256" -Encoding ascii
    Write-Output "Installer: $setup"
    Write-Output "SHA256: $hash"
} finally {
    $resolved = [IO.Path]::GetFullPath($stage)
    $prefix = [IO.Path]::GetFullPath($releaseRoot) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe installer staging path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
