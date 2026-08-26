@echo off
setlocal
set "ROOT=%~dp0"
set "ENGINE_DIR=%ROOT%runtime\uzdoom-experimental"
set "ENGINE=%ENGINE_DIR%\uzdoom.exe"
set "CONFIG=%ROOT%runtime\DoomTopMode.ini"
set "IWAD=%ROOT%runtime\DOOM2.WAD"
set "VOXELS=%ROOT%runtime\VoxelDoom_v2.4.pk3"
set "MOD=%ROOT%build\DoomTopMode.pk3"

if not exist "%ENGINE%" goto missing
if not exist "%IWAD%" goto missing
if not exist "%MOD%" goto missing

start "Doom Top Mode - MAP29 Projectile Test" /D "%ENGINE_DIR%" "%ENGINE%" -config "%CONFIG%" -iwad "%IWAD%" -file "%VOXELS%" "%MOD%" -warp 29 +r_ortho_cutaway 0.0 +r_ortho_wallcutout 104 +r_ortho_hidesky 1 +gl_no_skyclear 1 +crosshair 0
exit /b 0

:missing
echo A required Doom Top Mode file is missing.
echo Folder: %ROOT%
pause
exit /b 1

