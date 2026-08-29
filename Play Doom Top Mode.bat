@echo off
setlocal
pushd "%~dp0"
if exist "%~dp0DoomTopModeLauncher.exe" (
    "%~dp0DoomTopModeLauncher.exe" %*
    set "DOOMTOP_EXIT=%ERRORLEVEL%"
    goto :finished
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
set "DOOMTOP_EXIT=%ERRORLEVEL%"
:finished
popd
if not "%DOOMTOP_EXIT%"=="0" (
    echo.
    echo Doom Top Mode could not be started. Error code: %DOOMTOP_EXIT%
    pause
)
exit /b %DOOMTOP_EXIT%
