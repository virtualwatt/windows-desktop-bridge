@echo off
rem Start the Windows desktop bridge MCP server.
rem Run install_bridge.bat first (installs Python, uv, OBS Studio
rem and syncs dependencies). This file only starts the server.

cd /d "%~dp0"

rem --- Settings -------------------------------------------------------
rem BRIDGE_TOKEN must match the token entered on the Muse side
rem (Secure Vault / connector credential flow). Set it once for your
rem Windows user, e.g.:  setx BRIDGE_TOKEN "<long random token>"
rem Do not write the real token into this file.

if "%BRIDGE_TOKEN%"=="" (
    echo BRIDGE_TOKEN is not set.
    echo Generate a long random token on this machine and set it once:
    echo   setx BRIDGE_TOKEN "your-long-random-token"
    echo then open a new terminal and run this file again.
    pause
    exit /b 1
)

rem OBS Studio WebSocket settings. OBS_PROFILE is the recording
rem profile used on connect; OBS_WS_PASSWORD only if OBS auth is on.
if "%OBS_PROFILE%"=="" set OBS_PROFILE=Work
rem set OBS_WS_PASSWORD=
rem set OBS_WS_HOST=127.0.0.1
rem set OBS_WS_PORT=4455

rem --- OBS --------------------------------------------------------------
rem Launch OBS minimized with the bridge profile and scene collection
rem if it is not already running. Working directory must be the folder
rem containing obs64.exe.
tasklist /FI "IMAGENAME eq obs64.exe" 2>nul | find /I "obs64.exe" >nul
if %errorlevel% equ 0 (
    echo OBS is already running.
) else (
    echo Starting OBS with profile %OBS_PROFILE%...
    start "" /D "%ProgramFiles%\obs-studio\bin\64bit" "%ProgramFiles%\obs-studio\bin\64bit\obs64.exe" --profile "%OBS_PROFILE%" --collection "%OBS_PROFILE%" --minimize-to-tray --disable-updater
    timeout /t 5 /nobreak >nul
)

rem --- Bind address -----------------------------------------------------
rem Default: localhost only. If Tailscale is up, bind to this machine's
rem Tailscale IP instead, so the bridge is reachable inside the tailnet
rem (and only there). Set BRIDGE_HOST manually to override.
if "%BRIDGE_HOST%"=="" (
    for /f "delims=" %%i in ('tailscale ip -4 2^>nul') do set BRIDGE_HOST=%%i
)
if "%BRIDGE_HOST%"=="" set BRIDGE_HOST=127.0.0.1

rem --- Run ------------------------------------------------------------
echo Starting bridge on http://%BRIDGE_HOST%:8765/mcp (OBS profile: %OBS_PROFILE%)
uv run python windows_desktop_bridge.py
pause
