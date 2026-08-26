param([string]$Version = '0.1.0-experimental')

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$releaseRoot = Join-Path $root 'release'
$bundle = Join-Path $releaseRoot "Tuins-Top-Doom-$Version"
$archive = "$bundle.zip"
$engine = Join-Path $root 'runtime\uzdoom-experimental'
$compiler = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

& (Join-Path $root 'build.ps1')
if (-not (Test-Path -LiteralPath $engine)) { throw 'Customized UZDoom runtime is missing.' }
if (-not (Test-Path -LiteralPath $compiler)) { throw 'The Windows C# compiler is missing.' }

New-Item -ItemType Directory -Path $releaseRoot -Force | Out-Null
if (Test-Path -LiteralPath $bundle) {
    $resolvedRelease = [IO.Path]::GetFullPath($releaseRoot).TrimEnd('\') + '\'
    $resolvedBundle = [IO.Path]::GetFullPath($bundle)
    if (-not $resolvedBundle.StartsWith($resolvedRelease, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to replace bundle outside the release directory: $resolvedBundle"
    }
    Remove-Item -LiteralPath $resolvedBundle -Recurse -Force
}
New-Item -ItemType Directory -Path $bundle,(Join-Path $bundle 'engine') -Force | Out-Null

$launcher = Join-Path $bundle 'DoomTopModeLauncher.exe'
& $compiler /nologo /target:winexe /optimize+ `
    /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll `
    "/win32icon:$root\assets\DoomTopMode.ico" `
    "/out:$launcher" (Join-Path $root 'launcher\DoomTopModeLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed.' }

Copy-Item -LiteralPath (Join-Path $root 'build\DoomTopMode.pk3') -Destination $bundle -Force
Copy-Item -LiteralPath (Join-Path $root 'assets\DoomTopMode.ico') -Destination $bundle -Force
Copy-Item -LiteralPath (Join-Path $root 'release-files\README.txt') -Destination $bundle -Force
Get-ChildItem -LiteralPath $engine -File | Copy-Item -Destination (Join-Path $bundle 'engine') -Force

if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
Compress-Archive -Path (Join-Path $bundle '*') -DestinationPath $archive -CompressionLevel Optimal
Write-Host "Release ready: $archive"
