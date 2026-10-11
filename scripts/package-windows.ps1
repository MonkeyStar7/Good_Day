[CmdletBinding()]
param([switch]$InternalReview)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    $versionMatch = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'
    if (-not $versionMatch) { throw 'Expected a version and build number in pubspec.yaml.' }
    $version = $versionMatch.Matches[0].Groups[1].Value
    $buildNumber = $versionMatch.Matches[0].Groups[2].Value

    $buildArguments = @('build', 'windows', '--release')
    if ($InternalReview) { $buildArguments += '--dart-define=INTERNAL_REVIEW=true' }
    & flutter @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed.' }

    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere)) { throw 'Visual Studio locator not found.' }
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $visualStudio) { throw 'Visual Studio C++ build tools not found.' }
    $redistRoot = Join-Path $visualStudio 'VC/Redist/MSVC'
    $redistVersion = Get-ChildItem -LiteralPath $redistRoot -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $redistVersion) { throw 'Visual C++ redistributable directory not found.' }
    $crt = Get-ChildItem -LiteralPath (Join-Path $redistVersion.FullName 'x64') -Directory -Filter '*.CRT' |
        Select-Object -First 1
    if (-not $crt) { throw 'Visual C++ x64 CRT not found.' }

    $releaseRoot = Join-Path $projectRoot 'build/releases'
    New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
    $stageRoot = Join-Path $releaseRoot ('stage-' + [guid]::NewGuid().ToString('N'))
    $bundleName = if ($InternalReview) { 'Good Day Internal' } else { 'Good Day' }
    $bundle = Join-Path $stageRoot $bundleName
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    try {
        $compiled = Join-Path $projectRoot 'build/windows/x64/runner/Release'
        Get-ChildItem -LiteralPath $compiled | Copy-Item -Destination $bundle -Recurse -Force
        Get-ChildItem -LiteralPath $crt.FullName -Filter '*.dll' | Copy-Item -Destination $bundle -Force
        Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $bundle 'README.md')
        Copy-Item -LiteralPath (Join-Path $projectRoot 'docs') -Destination (Join-Path $bundle 'docs') -Recurse
        if ($InternalReview) {
            Copy-Item -LiteralPath (Join-Path $projectRoot 'docs/todo-review.md') -Destination (Join-Path $bundle 'INTERNAL-REVIEW.md')
        }
        $commit = & git rev-parse HEAD
        if ($LASTEXITCODE -ne 0) { throw 'Unable to read source commit.' }
        $channel = if ($InternalReview) { 'internal review' } else { 'release' }
        "Good Day $version+$buildNumber`nSource commit: $commit`nPlatform: Windows x64`nChannel: $channel" |
            Set-Content -LiteralPath (Join-Path $bundle 'VERSION.txt') -Encoding UTF8
        foreach ($required in @('good_day.exe', 'flutter_windows.dll', 'app_icon.ico', 'data/app.so', 'data/icudtl.dat', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
            if (-not (Test-Path -LiteralPath (Join-Path $bundle $required))) { throw "Missing package file: $required" }
        }
        $internalSuffix = if ($InternalReview) { '-internal' } else { '' }
        $archive = Join-Path $releaseRoot "Good-Day-$version$internalSuffix-windows-x64.zip"
        Compress-Archive -LiteralPath $bundle -DestinationPath $archive -Force
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
        "$hash  $(Split-Path $archive -Leaf)" | Set-Content -LiteralPath "$archive.sha256" -Encoding ASCII
        Write-Output "Package: $archive"
        Write-Output "SHA256: $hash"
    }
    finally {
        $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
        $expectedPrefix = [IO.Path]::GetFullPath($releaseRoot) + [IO.Path]::DirectorySeparatorChar
        if (-not $resolvedStage.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a staging directory outside build/releases.'
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}
finally {
    Pop-Location
}
