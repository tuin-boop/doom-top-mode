$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$runtimeDir = Join-Path $projectRoot 'runtime'
$engineDir = Join-Path $runtimeDir 'uzdoom'
$engineArchive = Join-Path $runtimeDir 'uzdoom-5.0.0-rc.3.zip'
$voxelPack = Join-Path $runtimeDir 'VoxelDoom_v2.4.pk3'
$wadDestination = Join-Path $runtimeDir 'DOOM2.WAD'

New-Item -ItemType Directory -Force -Path $runtimeDir, $engineDir | Out-Null

if (-not (Test-Path -LiteralPath (Join-Path $engineDir 'uzdoom.exe'))) {
    Write-Host 'Downloading UZDoom 5.0.0 RC3...'
    Invoke-WebRequest -UseBasicParsing `
        -Uri 'https://github.com/UZDoom/UZDoom/releases/download/5.0.0-rc.3/Windows-UZDoom-Release-x86_64.zip' `
        -OutFile $engineArchive
    Expand-Archive -LiteralPath $engineArchive -DestinationPath $engineDir -Force
}

if (-not (Test-Path -LiteralPath $wadDestination)) {
    $wadCandidates = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\base\doom2\DOOM2.WAD',
        'C:\Program Files (x86)\Steam\steamapps\common\Ultimate Doom\rerelease\DOOM2.WAD',
        'C:\Program Files\Steam\steamapps\common\Ultimate Doom\base\doom2\DOOM2.WAD'
    )
    if ($env:DOOMWADDIR) {
        $wadCandidates += Join-Path $env:DOOMWADDIR 'DOOM2.WAD'
    }
    $installedWad = $wadCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $installedWad) {
        throw 'Could not locate an installed DOOM2.WAD. Copy your legal WAD to runtime\DOOM2.WAD.'
    }
    Copy-Item -LiteralPath $installedWad -Destination $wadDestination
}

if (-not (Test-Path -LiteralPath $voxelPack)) {
    $voxelCandidates = @(
        (Join-Path $env:USERPROFILE 'Downloads\VoxelDoom_v2.4.pk3'),
        (Join-Path $projectRoot 'VoxelDoom_v2.4.pk3')
    )
    $installedVoxels = $voxelCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($installedVoxels) {
        Copy-Item -LiteralPath $installedVoxels -Destination $voxelPack
    }
    else {
        Write-Warning 'VoxelDoom_v2.4.pk3 was not found. The prototype will still run without voxels.'
    }
}

Write-Host 'Runtime ready.'
Write-Host 'Run .\play.ps1 to launch the prototype.'
