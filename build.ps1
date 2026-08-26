$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$sourceDir = Join-Path $projectRoot 'mod'
$buildDir = Join-Path $projectRoot 'build'
$packagePath = Join-Path $buildDir 'DoomTopMode.pk3'
$zipPath = Join-Path $buildDir 'DoomTopMode.build.zip'

if (-not (Test-Path -LiteralPath $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

# Do not touch an up-to-date package. UZDoom keeps loaded PK3 files open, so
# rebuilding an unchanged package while a game is running would fail here.
if (Test-Path -LiteralPath $packagePath) {
    $packageTime = (Get-Item -LiteralPath $packagePath).LastWriteTimeUtc
    $latestSourceTime = Get-ChildItem -LiteralPath $sourceDir -File -Recurse |
        Measure-Object -Property LastWriteTimeUtc -Maximum |
        Select-Object -ExpandProperty Maximum
    if ($null -ne $latestSourceTime -and $packageTime -ge $latestSourceTime) {
        Write-Host "Up to date: $packagePath"
        return
    }
}

if (Test-Path -LiteralPath $packagePath) {
    try {
        Remove-Item -LiteralPath $packagePath
    }
    catch [System.IO.IOException] {
        throw 'DoomTopMode.pk3 is in use. Close UZDoom once so changed mod files can be rebuilt.'
    }
}
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath
}

# Windows PowerShell's Compress-Archive validates the extension even though a
# PK3 is structurally a ZIP archive. Build as ZIP, then give it its PK3 name.
Compress-Archive -Path (Join-Path $sourceDir '*') -DestinationPath $zipPath
Move-Item -LiteralPath $zipPath -Destination $packagePath
Write-Host "Built $packagePath"
