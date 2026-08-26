param(
    [string]$Map = 'MAP01',
    [switch]$NoVoxels,
    [ValidateRange(0.0, 0.95)]
    [double]$Cutaway = 0.0,
    [ValidateRange(0.0, 512.0)]
    [double]$WallCutout = 104.0,
    [switch]$ExperimentalRenderer,
    [switch]$StockRenderer,
    [switch]$ShowSky
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build.ps1')

$stockEngine = Join-Path $PSScriptRoot 'runtime\uzdoom\uzdoom.exe'
$cutawayEngine = Join-Path $PSScriptRoot 'runtime\uzdoom-cutaway\uzdoom.exe'
$experimentalEngine = Join-Path $PSScriptRoot 'runtime\uzdoom-experimental\uzdoom.exe'
$engine = if ($ExperimentalRenderer) {
    if (-not (Test-Path -LiteralPath $experimentalEngine)) { throw 'Experimental UZDoom renderer is missing.' }
    $experimentalEngine
} elseif (-not $StockRenderer -and (Test-Path -LiteralPath $cutawayEngine)) {
    $cutawayEngine
} else {
    $stockEngine
}
$iwad = Join-Path $PSScriptRoot 'runtime\DOOM2.WAD'
$mod = Join-Path $PSScriptRoot 'build\DoomTopMode.pk3'
$voxels = Join-Path $PSScriptRoot 'runtime\VoxelDoom_v2.4.pk3'
$config = Join-Path $PSScriptRoot 'runtime\DoomTopMode.ini'

if (-not (Test-Path -LiteralPath $engine)) { throw 'UZDoom is missing. Run setup.ps1 first.' }
if (-not (Test-Path -LiteralPath $iwad)) { throw 'DOOM2.WAD is missing. Run setup.ps1 first.' }

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DoomTopWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
}
'@

function Show-DoomTopWindow([System.Diagnostics.Process]$Process) {
    Write-Host 'Loading Doom Top Mode (the voxel pack can take a while)...'
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Process.HasExited) {
            throw "UZDoom exited while starting. Error code: $($Process.ExitCode)"
        }
        $Process.Refresh()
        if ($Process.MainWindowHandle -ne 0) {
            [DoomTopWindow]::ShowWindow($Process.MainWindowHandle, 9) | Out-Null
            [DoomTopWindow]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
            Write-Host 'Doom Top Mode is ready.'
            return
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Warning 'UZDoom is still loading in the background.'
}

# A second launch cannot rebuild a PK3 held by the first game. Treat the batch
# file as a convenient "show the game" button when this build is already open.
$enginePath = [System.IO.Path]::GetFullPath($engine)
$existing = Get-Process uzdoom -ErrorAction SilentlyContinue | Where-Object {
    try { [System.IO.Path]::GetFullPath($_.Path) -eq $enginePath } catch { $false }
} | Select-Object -First 1
if ($existing) {
    Show-DoomTopWindow $existing
    return
}

$launchArgs = @('-config', $config, '-iwad', $iwad, '-file')
if (-not $NoVoxels -and (Test-Path -LiteralPath $voxels)) { $launchArgs += $voxels }
$launchArgs += @(
    $mod,
    '+r_ortho_cutaway', $Cutaway.ToString([Globalization.CultureInfo]::InvariantCulture),
    '+r_ortho_wallcutout', $WallCutout.ToString([Globalization.CultureInfo]::InvariantCulture),
    '+r_ortho_hidesky', $(if ($ShowSky) { '0' } else { '1' }),
    '+gl_no_skyclear', $(if ($ShowSky) { '0' } else { '1' }),
    '+crosshair', '0',
    '+bind', 'q', 'dtm_cam_left',
    '+bind', 'e', 'dtm_cam_right',
    '+bind', 'c', 'dtm_toggle_aim',
    '+bind', 'f', 'dtm_toggle_flashlight',
    '+bind', 'b', 'dtm_toggle_auto_camera',
    '+bind', 'n', 'dtm_toggle_wall_cutout',
    '+bind', 'z', 'dtm_cam_center',
    '+bind', 'v', 'dtm_cam_pitch',
    '+bind', 'rightbracket', 'dtm_zoom_in',
    '+bind', 'leftbracket', 'dtm_zoom_out',
    '+map', $Map
)

$started = Start-Process -FilePath $engine -ArgumentList $launchArgs -WorkingDirectory (Split-Path $engine) -WindowStyle Normal -PassThru
Show-DoomTopWindow $started
