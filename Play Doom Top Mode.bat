@echo off
setlocal
pushd "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" %*
set "DOOMTOP_EXIT=%ERRORLEVEL%"
popd
if not "%DOOMTOP_EXIT%"=="0" (
    echo.
    echo Doom Top Mode could not be started. Error code: %DOOMTOP_EXIT%
    pause
)
exit /b %DOOMTOP_EXIT%
